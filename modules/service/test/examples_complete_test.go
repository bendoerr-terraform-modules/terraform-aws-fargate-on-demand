package test_test

import (
	"context"
	"net/url"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestServiceParkedAtZero(t *testing.T) {
	t.Parallel()

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

	defer terraform.DestroyContext(t, context.Background(), terraformOptions)
	terraform.InitAndApplyContext(t, context.Background(), terraformOptions)

	clusterName := terraform.OutputContext(t, context.Background(), terraformOptions, "ecs_cluster_name")
	serviceName := terraform.OutputContext(t, context.Background(), terraformOptions, "ecs_service_name")
	topicArn := terraform.OutputContext(t, context.Background(), terraformOptions, "events_topic_arn")
	roleName := terraform.OutputContext(t, context.Background(), terraformOptions, "service_role_name")
	controlPolicyArn := terraform.OutputContext(t, context.Background(), terraformOptions, "svc_control_policy_arn")

	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("us-east-1"))
	if err != nil {
		t.Fatal(err)
	}

	// Service exists on the module's cluster, ACTIVE, parked at zero.
	ecsClient := ecs.NewFromConfig(cfg)
	svcOut, err := ecsClient.DescribeServices(context.TODO(), &ecs.DescribeServicesInput{
		Cluster:  aws.String(clusterName),
		Services: []string{serviceName},
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

	// The registered task definition is ACTIVE.
	tdOut, err := ecsClient.DescribeTaskDefinition(context.TODO(), &ecs.DescribeTaskDefinitionInput{
		TaskDefinition: svc.TaskDefinition,
	})
	if err != nil {
		t.Fatal(err)
	}
	if string(tdOut.TaskDefinition.Status) != "ACTIVE" {
		t.Errorf("task definition status should be ACTIVE, got %q", tdOut.TaskDefinition.Status)
	}

	// The task role trusts ecs-tasks.amazonaws.com.
	iamClient := iam.NewFromConfig(cfg)
	role, err := iamClient.GetRole(context.TODO(), &iam.GetRoleInput{RoleName: aws.String(roleName)})
	if err != nil {
		t.Fatal(err)
	}
	doc, err := url.QueryUnescape(aws.ToString(role.Role.AssumeRolePolicyDocument))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(doc, "ecs-tasks.amazonaws.com") {
		t.Errorf("assume-role policy does not trust ecs-tasks.amazonaws.com: %s", doc)
	}

	// The launcher-control policy the module exports is a real, reachable policy.
	_, err = iamClient.GetPolicy(context.TODO(), &iam.GetPolicyInput{
		PolicyArn: aws.String(controlPolicyArn),
	})
	if err != nil {
		t.Errorf("svc control policy not reachable: %v", err)
	}

	// The events topic is real and reachable.
	snsClient := sns.NewFromConfig(cfg)
	_, err = snsClient.GetTopicAttributes(context.TODO(), &sns.GetTopicAttributesInput{
		TopicArn: aws.String(topicArn),
	})
	if err != nil {
		t.Errorf("events topic not reachable: %v", err)
	}
}
