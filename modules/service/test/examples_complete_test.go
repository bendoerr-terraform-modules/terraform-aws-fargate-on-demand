package test_test

import (
	"context"
	"net/url"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// IAM reads are globally eventually consistent; a fresh client can NoSuchEntity
// on a just-created role or policy. Retry the read a few times before treating
// the error as real — a single flake here costs a full serialized-matrix rerun.
func withRetry[T any](t *testing.T, what string, fn func() (T, error)) T {
	t.Helper()
	var out T
	var err error
	for attempt := range 5 {
		out, err = fn()
		if err == nil {
			return out
		}
		t.Logf("%s attempt %d: %v (retrying)", what, attempt+1, err)
		time.Sleep(3 * time.Second)
	}
	t.Fatalf("%s failed after retries: %v", what, err)
	return out
}

// Exact key-set assertion (the efs-access lesson from #555): every output is
// non-null here, so all five must be present — a typo'd or renamed output is a
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

// Service exists on the module's cluster, ACTIVE, parked at zero; returns the
// registered task definition ARN for the shape assertions.
func assertServiceParked(t *testing.T, ctx context.Context, ecsClient *ecs.Client, cluster, service string) *string {
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
	return svc.TaskDefinition
}

// The task definition is ACTIVE and carries the example's declared shape: the
// cpu/memory strings and two containers (service alpine + watchdog).
func assertTaskDefinitionShape(t *testing.T, ctx context.Context, ecsClient *ecs.Client, taskDefArn *string) {
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
	if len(td.ContainerDefinitions) != 2 {
		t.Errorf("task definition should carry 2 containers (service + watchdog), got %d",
			len(td.ContainerDefinitions))
	}
	sawAlpine := false
	for _, c := range td.ContainerDefinitions {
		if strings.Contains(aws.ToString(c.Image), "alpine") {
			sawAlpine = true
		}
	}
	if !sawAlpine {
		t.Errorf("no container uses the example's alpine image")
	}
}

// The task role trusts ecs-tasks.amazonaws.com, and the launcher-control policy
// grants the action the launcher lives on — assert the DOCUMENT, not mere
// existence (existence is already implied by a successful apply).
func assertIAMWiring(t *testing.T, ctx context.Context, iamClient *iam.Client, roleName, controlPolicyArn string) {
	t.Helper()
	role := withRetry(t, "iam.GetRole", func() (*iam.GetRoleOutput, error) {
		return iamClient.GetRole(ctx, &iam.GetRoleInput{RoleName: aws.String(roleName)})
	})
	doc, err := url.QueryUnescape(aws.ToString(role.Role.AssumeRolePolicyDocument))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(doc, "ecs-tasks.amazonaws.com") {
		t.Errorf("assume-role policy does not trust ecs-tasks.amazonaws.com: %s", doc)
	}

	pol := withRetry(t, "iam.GetPolicy", func() (*iam.GetPolicyOutput, error) {
		return iamClient.GetPolicy(ctx, &iam.GetPolicyInput{PolicyArn: aws.String(controlPolicyArn)})
	})
	polVer := withRetry(t, "iam.GetPolicyVersion", func() (*iam.GetPolicyVersionOutput, error) {
		return iamClient.GetPolicyVersion(ctx, &iam.GetPolicyVersionInput{
			PolicyArn: aws.String(controlPolicyArn),
			VersionId: pol.Policy.DefaultVersionId,
		})
	})
	polDoc, err := url.QueryUnescape(aws.ToString(polVer.PolicyVersion.Document))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(polDoc, "ecs:UpdateService") {
		t.Errorf("control policy document does not grant ecs:UpdateService: %s", polDoc)
	}
}

// The events topic exists, and with sns_kms_key_id = null it must carry no KMS
// master key (an unexpected key means the null wiring regressed).
func assertTopicUnencrypted(t *testing.T, ctx context.Context, snsClient *sns.Client, topicArn string) {
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
		"service_role_name", "svc_control_policy_arn",
	})

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		t.Fatal(err)
	}
	ecsClient := ecs.NewFromConfig(cfg)

	taskDefArn := assertServiceParked(t, ctx, ecsClient, vals["ecs_cluster_name"], vals["ecs_service_name"])
	assertTaskDefinitionShape(t, ctx, ecsClient, taskDefArn)
	assertIAMWiring(t, ctx, iam.NewFromConfig(cfg), vals["service_role_name"], vals["svc_control_policy_arn"])
	assertTopicUnencrypted(t, ctx, sns.NewFromConfig(cfg), vals["events_topic_arn"])
}
