package test_test

import (
	"context"
	"fmt"
	"net/url"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	cwtypes "github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// Pinned defaults from spec §4.1 / modules/service/ecs-task.tf's
// custodian_default_images. A change here should also bump the module.
const (
	tcpCustodianImage       = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-custodian:0.1.3"
	minecraftCustodianImage = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-minecraft-custodian:v0.1.0"
)

// Exact key-set assertion (the efs-access lesson from #555): every output is
// non-null here, so all keys must be present — a typo'd or renamed output is a
// red, not a silently-absent key.
func outputStrings(t *testing.T, outputs map[string]interface{}, wantKeys []string) map[string]string {
	t.Helper()
	sort.Strings(wantKeys)
	gotKeys := make([]string, 0, len(outputs))
	for k := range outputs {
		gotKeys = append(gotKeys, k)
	}
	sort.Strings(gotKeys)
	if !reflect.DeepEqual(wantKeys, gotKeys) {
		t.Fatalf("output key set should be %v, got %v", wantKeys, gotKeys)
	}
	vals := make(map[string]string, len(wantKeys))
	for _, k := range wantKeys {
		v, _ := outputs[k].(string)
		if v == "" {
			t.Fatalf("output %q should be a non-empty string, got %#v", k, outputs[k])
		}
		vals[k] = v
	}
	return vals
}

// Service exists on the module's cluster, ACTIVE, parked at zero, with the
// deployment percents and capacity provider spec §4.3 fixes for every kind;
// returns the registered task definition ARN for the shape assertions.
func assertServiceParked(ctx context.Context, t *testing.T, ecsClient *ecs.Client, cluster, service, wantCapacityProvider string) *string {
	t.Helper()
	svcOut, err := ecsClient.DescribeServices(ctx, &ecs.DescribeServicesInput{
		Cluster:  aws.String(cluster),
		Services: []string{service},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(svcOut.Services) != 1 {
		t.Fatalf("expected exactly 1 service, got %d", len(svcOut.Services))
	}
	svc := svcOut.Services[0]
	if aws.ToString(svc.Status) != "ACTIVE" {
		t.Errorf("service status should be ACTIVE, got %q", aws.ToString(svc.Status))
	}
	if svc.DesiredCount != 0 {
		t.Errorf("desired count should be 0 (scale-to-zero is the native state), got %d", svc.DesiredCount)
	}

	// spec §4.3.1: deployment_maximum_percent = 100, deployment_minimum_healthy_percent = 0
	// for every kind, so no deployment ever runs two tasks against one EFS volume.
	if svc.DeploymentConfiguration == nil ||
		aws.ToInt32(svc.DeploymentConfiguration.MaximumPercent) != 100 ||
		aws.ToInt32(svc.DeploymentConfiguration.MinimumHealthyPercent) != 0 {
		t.Errorf("deployment_maximum_percent/deployment_minimum_healthy_percent should be 100/0, got %+v", svc.DeploymentConfiguration)
	}

	// spec §4.3.2: capacity_provider_strategy.capacity_provider = var.capacity_provider.
	if len(svc.CapacityProviderStrategy) != 1 || aws.ToString(svc.CapacityProviderStrategy[0].CapacityProvider) != wantCapacityProvider {
		t.Errorf("capacity provider strategy should be a single %q entry, got %+v", wantCapacityProvider, svc.CapacityProviderStrategy)
	}

	return svc.TaskDefinition
}

// Fetches the task definition and asserts it is ACTIVE with the example's
// declared cpu/memory.
func describeTaskDefinition(ctx context.Context, t *testing.T, ecsClient *ecs.Client, taskDefArn *string) *types.TaskDefinition {
	t.Helper()
	tdOut, err := ecsClient.DescribeTaskDefinition(ctx, &ecs.DescribeTaskDefinitionInput{
		TaskDefinition: taskDefArn,
	})
	if err != nil {
		t.Fatal(err)
	}
	td := tdOut.TaskDefinition
	if td.Status != types.TaskDefinitionStatusActive {
		t.Errorf("task definition status should be ACTIVE, got %q", td.Status)
	}
	if aws.ToString(td.Cpu) != "256" || aws.ToString(td.Memory) != "512" {
		t.Errorf("task definition cpu/memory should be 256/512, got %s/%s",
			aws.ToString(td.Cpu), aws.ToString(td.Memory))
	}
	return td
}

func envMap(env []types.KeyValuePair) map[string]string {
	m := make(map[string]string, len(env))
	for _, kv := range env {
		m[aws.ToString(kv.Name)] = aws.ToString(kv.Value)
	}
	return m
}

// The task definition carries exactly 2 containers (app + watchdog); the app
// container is identified by the example's alpine image, the watchdog is
// whichever container is left. Fails the test (fatal) if that shape doesn't
// hold, since every other assertion in this file depends on it.
func splitContainers(t *testing.T, td *types.TaskDefinition) (app, sidecar *types.ContainerDefinition) {
	t.Helper()
	if len(td.ContainerDefinitions) != 2 {
		t.Fatalf("task definition should carry 2 containers (service + watchdog), got %d", len(td.ContainerDefinitions))
	}
	for i := range td.ContainerDefinitions {
		c := &td.ContainerDefinitions[i]
		if strings.Contains(aws.ToString(c.Image), "alpine") {
			app = c
		} else {
			sidecar = c
		}
	}
	if app == nil || sidecar == nil {
		t.Fatalf("could not identify app/watchdog containers by image: %+v", td.ContainerDefinitions)
	}
	return app, sidecar
}

// kind = "tcp" sidecar (spec §6.1.1 / §4.2): the pinned 0.1.3 image,
// WATCH_TCP = 30000 (the example doesn't override custodian.tcp_port), no
// health check, and the app container carries no dependsOn (that's a
// "minecraft"-only addition).
func assertTcpTaskDefinitionShape(t *testing.T, td *types.TaskDefinition) {
	t.Helper()
	app, sidecar := splitContainers(t, td)

	if aws.ToString(sidecar.Image) != tcpCustodianImage {
		t.Errorf("tcp sidecar image should be %q, got %q", tcpCustodianImage, aws.ToString(sidecar.Image))
	}
	if got := envMap(sidecar.Environment)["WATCH_TCP"]; got != "30000" {
		t.Errorf("tcp sidecar WATCH_TCP should be \"30000\" (the example's default tcp_port), got %q", got)
	}
	if sidecar.HealthCheck != nil {
		t.Errorf("tcp sidecar should carry no health check, got %+v", sidecar.HealthCheck)
	}
	if len(app.DependsOn) != 0 {
		t.Errorf("tcp app container should carry no dependsOn, got %+v", app.DependsOn)
	}
}

// kind = "minecraft" task definition (spec §6.1.2 / §4.2): sidecar env names
// and values, health check, timeouts, the app container's dependsOn on the
// sidecar, and runtimePlatform.cpuArchitecture = ARM64 (the example's
// cpu_architecture override).
func assertMinecraftTaskDefinitionShape(t *testing.T, td *types.TaskDefinition, wantClusterName, wantServiceName, wantDNSZoneID, wantDNSRecord, wantSNSTopicArn string) {
	t.Helper()
	app, sidecar := splitContainers(t, td)

	if aws.ToString(sidecar.Image) != minecraftCustodianImage {
		t.Errorf("minecraft sidecar image should be %q, got %q", minecraftCustodianImage, aws.ToString(sidecar.Image))
	}
	if !aws.ToBool(sidecar.Essential) {
		t.Errorf("minecraft sidecar should be essential = true")
	}

	wantEnv := map[string]string{
		"CUSTODIAN_CLUSTER":       wantClusterName,
		"CUSTODIAN_SERVICE":       wantServiceName,
		"CUSTODIAN_DNS_ZONE_ID":   wantDNSZoneID,
		"CUSTODIAN_DNS_RECORD":    wantDNSRecord,
		"CUSTODIAN_SNS_TOPIC_ARN": wantSNSTopicArn,
		"CUSTODIAN_IDLE_TIMEOUT":  "600s", // "${var.idle_seconds}s"; the example doesn't override idle_seconds (default "600").
	}
	gotEnv := envMap(sidecar.Environment)
	for name, want := range wantEnv {
		if got := gotEnv[name]; got != want {
			t.Errorf("minecraft sidecar env %s should be %q, got %q", name, want, got)
		}
	}

	if sidecar.HealthCheck == nil {
		t.Fatalf("minecraft sidecar should carry a health check")
	}
	hc := sidecar.HealthCheck
	if !reflect.DeepEqual(hc.Command, []string{"CMD", "/custodian", "healthcheck"}) {
		t.Errorf("minecraft sidecar health check command should be [CMD /custodian healthcheck], got %v", hc.Command)
	}
	if aws.ToInt32(hc.Interval) != 5 || aws.ToInt32(hc.Timeout) != 2 || aws.ToInt32(hc.StartPeriod) != 240 || aws.ToInt32(hc.Retries) != 3 {
		t.Errorf("minecraft sidecar health check should be interval=5 timeout=2 startPeriod=240 retries=3, got %+v", hc)
	}
	if aws.ToInt32(sidecar.StartTimeout) != 120 {
		t.Errorf("minecraft sidecar startTimeout should be 120, got %d", aws.ToInt32(sidecar.StartTimeout))
	}
	if aws.ToInt32(sidecar.StopTimeout) != 120 {
		t.Errorf("minecraft sidecar stopTimeout should be 120, got %d", aws.ToInt32(sidecar.StopTimeout))
	}

	if len(app.DependsOn) != 1 ||
		aws.ToString(app.DependsOn[0].ContainerName) != aws.ToString(sidecar.Name) ||
		app.DependsOn[0].Condition != types.ContainerConditionHealthy {
		t.Errorf("minecraft app container dependsOn should be [{%s HEALTHY}], got %+v", aws.ToString(sidecar.Name), app.DependsOn)
	}
	if aws.ToInt32(app.StopTimeout) != 120 {
		t.Errorf("minecraft app stopTimeout should be 120, got %d", aws.ToInt32(app.StopTimeout))
	}

	if td.RuntimePlatform == nil || td.RuntimePlatform.CpuArchitecture != types.CPUArchitectureArm64 {
		t.Errorf("minecraft task definition runtimePlatform.cpuArchitecture should be ARM64, got %+v", td.RuntimePlatform)
	}
}

// The task role trusts ecs-tasks.amazonaws.com, and the launcher-control
// policy grants ecs:UpdateService and, since this step, ecs:ListTasks scoped
// to this service's own cluster via an ArnEquals ecs:cluster condition (spec
// §4.4) — assert the DOCUMENT, not mere existence.
func assertIAMWiring(ctx context.Context, t *testing.T, iamClient *iam.Client, ecsClient *ecs.Client, roleName, controlPolicyArn, clusterName string) {
	t.Helper()
	// IAM reads are globally eventually consistent; a fresh client can
	// NoSuchEntity on a just-created role or policy. Same retry budget as the
	// dns-record sibling (10 x 5s) — a flake here costs a serialized-matrix rerun.
	var role *iam.GetRoleOutput
	if _, err := retry.DoWithRetryContextE(t, ctx, "iam.GetRole", 10, 5*time.Second, func() (string, error) {
		var e error
		role, e = iamClient.GetRole(ctx, &iam.GetRoleInput{RoleName: aws.String(roleName)})
		return "", e
	}); err != nil {
		t.Fatal(err)
	}
	doc, err := url.PathUnescape(aws.ToString(role.Role.AssumeRolePolicyDocument))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(doc, "ecs-tasks.amazonaws.com") {
		t.Errorf("assume-role policy does not trust ecs-tasks.amazonaws.com: %s", doc)
	}

	var polVer *iam.GetPolicyVersionOutput
	if _, rerr := retry.DoWithRetryContextE(t, ctx, "iam.GetPolicy+Version", 10, 5*time.Second, func() (string, error) {
		pol, e := iamClient.GetPolicy(ctx, &iam.GetPolicyInput{PolicyArn: aws.String(controlPolicyArn)})
		if e != nil {
			return "", e
		}
		polVer, e = iamClient.GetPolicyVersion(ctx, &iam.GetPolicyVersionInput{
			PolicyArn: aws.String(controlPolicyArn),
			VersionId: pol.Policy.DefaultVersionId,
		})
		return "", e
	}); rerr != nil {
		t.Fatal(rerr)
	}
	polDoc, err := url.PathUnescape(aws.ToString(polVer.PolicyVersion.Document))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(polDoc, "ecs:UpdateService") {
		t.Errorf("control policy document does not grant ecs:UpdateService: %s", polDoc)
	}
	if !strings.Contains(polDoc, "ecs:ListTasks") {
		t.Errorf("control policy document does not grant ecs:ListTasks: %s", polDoc)
	}

	clustersOut, err := ecsClient.DescribeClusters(ctx, &ecs.DescribeClustersInput{Clusters: []string{clusterName}})
	if err != nil {
		t.Fatal(err)
	}
	if len(clustersOut.Clusters) != 1 {
		t.Fatalf("expected exactly 1 cluster named %q, got %d", clusterName, len(clustersOut.Clusters))
	}
	clusterArn := aws.ToString(clustersOut.Clusters[0].ClusterArn)
	if !strings.Contains(polDoc, "ArnEquals") || !strings.Contains(polDoc, clusterArn) {
		t.Errorf("control policy document does not scope ecs:ListTasks to this cluster (%s) via ArnEquals ecs:cluster: %s", clusterArn, polDoc)
	}
}

// The events topic exists, and with sns_kms_key_id = null it must carry no KMS
// master key (an unexpected key means the null wiring regressed).
func assertTopicUnencrypted(ctx context.Context, t *testing.T, snsClient *sns.Client, topicArn string) {
	t.Helper()
	attrs, err := snsClient.GetTopicAttributes(ctx, &sns.GetTopicAttributesInput{
		TopicArn: aws.String(topicArn),
	})
	if err != nil {
		t.Fatal(err)
	}
	if kms := attrs.Attributes["KmsMasterKeyId"]; kms != "" {
		t.Errorf("events topic should have no KMS key with sns_kms_key_id=null, got %q", kms)
	}
}

// spec §4.5 / §6.1.5: the max-runtime cost alarm exists, targets the alarms
// topic (not the notifications topic — the notice Lambdas would choke on
// alarm payloads), and carries the fixed namespace/metric/statistic/period
// plus evaluation_periods = datapoints_to_alarm = var.max_runtime_hours
// (default 12, unset by the example).
func assertMaxRuntimeAlarm(ctx context.Context, t *testing.T, cwClient *cloudwatch.Client, cluster, service, wantAlarmTopicArn string) {
	t.Helper()

	// CloudWatch alarm creation, like IAM, can lag a just-completed apply —
	// a fresh read can transiently see 0 alarms. Same retry budget as
	// assertIAMWiring (10 x 5s) so a flake here doesn't masquerade as a
	// regression.
	var out *cloudwatch.DescribeAlarmsForMetricOutput
	if _, err := retry.DoWithRetryContextE(t, ctx, "cloudwatch.DescribeAlarmsForMetric", 10, 5*time.Second, func() (string, error) {
		var e error
		out, e = cwClient.DescribeAlarmsForMetric(ctx, &cloudwatch.DescribeAlarmsForMetricInput{
			Namespace:  aws.String("AWS/ECS"),
			MetricName: aws.String("CPUUtilization"),
			Dimensions: []cwtypes.Dimension{
				{Name: aws.String("ClusterName"), Value: aws.String(cluster)},
				{Name: aws.String("ServiceName"), Value: aws.String(service)},
			},
		})
		if e != nil {
			return "", e
		}
		if len(out.MetricAlarms) != 1 {
			return "", fmt.Errorf("expected exactly 1 max-runtime alarm for %s/%s, got %d", cluster, service, len(out.MetricAlarms))
		}
		return "", nil
	}); err != nil {
		t.Fatal(err)
	}
	alarm := out.MetricAlarms[0]

	if alarm.Statistic != cwtypes.StatisticSampleCount {
		t.Errorf("alarm statistic should be SampleCount, got %q", alarm.Statistic)
	}
	if aws.ToInt32(alarm.Period) != 3600 {
		t.Errorf("alarm period should be 3600, got %d", aws.ToInt32(alarm.Period))
	}
	if aws.ToInt32(alarm.EvaluationPeriods) != 12 || aws.ToInt32(alarm.DatapointsToAlarm) != 12 {
		t.Errorf("alarm evaluation_periods/datapoints_to_alarm should both be 12 (max_runtime_hours default), got %d/%d",
			aws.ToInt32(alarm.EvaluationPeriods), aws.ToInt32(alarm.DatapointsToAlarm))
	}
	if aws.ToFloat64(alarm.Threshold) != 0 {
		t.Errorf("alarm threshold should be 0, got %v", aws.ToFloat64(alarm.Threshold))
	}
	if alarm.ComparisonOperator != cwtypes.ComparisonOperatorGreaterThanThreshold {
		t.Errorf("alarm comparison operator should be GreaterThanThreshold, got %q", alarm.ComparisonOperator)
	}
	if aws.ToString(alarm.TreatMissingData) != "notBreaching" {
		t.Errorf("alarm treat_missing_data should be notBreaching, got %q", aws.ToString(alarm.TreatMissingData))
	}

	found := false
	for _, a := range alarm.AlarmActions {
		if a == wantAlarmTopicArn {
			found = true
		}
	}
	if !found {
		t.Errorf("alarm_actions should contain the alarms topic %s, got %v", wantAlarmTopicArn, alarm.AlarmActions)
	}
}

func TestServiceParkedAtZero(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	// The example sources ../../../dns-record and ../../../persistence, so the
	// copied tree must be the repo root or those relative paths dangle.
	rootFolder := "../../../"
	terraformFolderRelativeToRoot := "modules/service/examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(
		t, rootFolder, terraformFolderRelativeToRoot,
	)

	// Lowercased: the namespace feeds a DNS zone name in the example.
	rndns := strings.ToLower(random.UniqueID())

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace": rndns,
		},
	}

	defer terraform.DestroyContext(t, ctx, terraformOptions)
	terraform.InitAndApplyContext(t, ctx, terraformOptions)

	vals := outputStrings(t, terraform.OutputAllContext(t, ctx, terraformOptions), []string{
		"ecs_cluster_name", "ecs_service_name", "events_topic_arn",
		"service_role_name", "svc_control_policy_arn", "alarm_topic_arn",
		"dns_zone_id",
		"mc_ecs_cluster_name", "mc_ecs_service_name", "mc_svc_control_policy_arn",
		"mc_alarm_topic_arn", "mc_dns_record", "mc_events_topic_arn", "mc_service_role_name",
	})

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		t.Fatal(err)
	}
	ecsClient := ecs.NewFromConfig(cfg)
	iamClient := iam.NewFromConfig(cfg)
	snsClient := sns.NewFromConfig(cfg)
	cwClient := cloudwatch.NewFromConfig(cfg)

	// kind = "tcp" (module default), FARGATE_SPOT (module default).
	tcpTaskDefArn := assertServiceParked(ctx, t, ecsClient, vals["ecs_cluster_name"], vals["ecs_service_name"], "FARGATE_SPOT")
	tcpTD := describeTaskDefinition(ctx, t, ecsClient, tcpTaskDefArn)
	assertTcpTaskDefinitionShape(t, tcpTD)
	assertIAMWiring(ctx, t, iamClient, ecsClient, vals["service_role_name"], vals["svc_control_policy_arn"], vals["ecs_cluster_name"])
	assertTopicUnencrypted(ctx, t, snsClient, vals["events_topic_arn"])
	assertMaxRuntimeAlarm(ctx, t, cwClient, vals["ecs_cluster_name"], vals["ecs_service_name"], vals["alarm_topic_arn"])

	// kind = "minecraft", ARM64, FARGATE (the example's overrides).
	mcTaskDefArn := assertServiceParked(ctx, t, ecsClient, vals["mc_ecs_cluster_name"], vals["mc_ecs_service_name"], "FARGATE")
	mcTD := describeTaskDefinition(ctx, t, ecsClient, mcTaskDefArn)
	assertMinecraftTaskDefinitionShape(t, mcTD,
		vals["mc_ecs_cluster_name"], vals["mc_ecs_service_name"],
		vals["dns_zone_id"], vals["mc_dns_record"], vals["mc_events_topic_arn"],
	)
	assertIAMWiring(ctx, t, iamClient, ecsClient, vals["mc_service_role_name"], vals["mc_svc_control_policy_arn"], vals["mc_ecs_cluster_name"])
	assertTopicUnencrypted(ctx, t, snsClient, vals["mc_events_topic_arn"])
	assertMaxRuntimeAlarm(ctx, t, cwClient, vals["mc_ecs_cluster_name"], vals["mc_ecs_service_name"], vals["mc_alarm_topic_arn"])
}
