package test

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/kr/pretty"
	"testing"
	"time"
)

func TestDefaults(t *testing.T) {
	t.Parallel()

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueId()

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace": rndns,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer terraform.Destroy(t, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// AWS Session
	cfg, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithRegion("us-east-1"),
	)

	if err != nil {
		t.Fatal(err)
	}

	_, _ = pretty.Print(terraform.OutputAll(t, terraformOptions))

	ecsClusterName := terraform.Output(t, terraformOptions, "ecs_cluster")
	ecsServiceName := terraform.Output(t, terraformOptions, "ecs_service")
	logGroupName := terraform.Output(t, terraformOptions, "log_group")
	logStreamName := random.UniqueId()

	ecsSvc := ecs.NewFromConfig(cfg)
	descSvcs, err := ecsSvc.DescribeServices(context.TODO(), &ecs.DescribeServicesInput{
		Services: []string{ecsServiceName},
		Cluster:  &ecsClusterName,
	})

	if err != nil {
		t.Fatal(err)
	}

	_, _ = pretty.Print(descSvcs.Services)

	if descSvcs.Services[0].DesiredCount != 0 {
		t.Fatal("service already has desired count greater than zero: ", descSvcs.Services[0].DesiredCount)
	}

	cwSvc := cloudwatchlogs.NewFromConfig(cfg)
	s := "Trigger Message"
	n := time.Now().UnixMilli()

	_, err = cwSvc.CreateLogStream(context.TODO(), &cloudwatchlogs.CreateLogStreamInput{
		LogGroupName:  &logGroupName,
		LogStreamName: &logStreamName,
	})

	if err != nil {
		t.Fatal(err)
	}

	outEvent, err := cwSvc.PutLogEvents(context.TODO(), &cloudwatchlogs.PutLogEventsInput{
		LogEvents: []types.InputLogEvent{{
			Message:   &s,
			Timestamp: &n,
		}},
		LogGroupName:  &logGroupName,
		LogStreamName: &logStreamName,
	})

	if err != nil {
		t.Fatal(err)
	}

	_, _ = pretty.Print(outEvent.RejectedLogEventsInfo)

	fmt.Println("sleeping now")
	time.Sleep(1 * 60 * time.Second)
	fmt.Println("awake")

	descSvcs, err = ecsSvc.DescribeServices(context.TODO(), &ecs.DescribeServicesInput{
		Services: []string{ecsServiceName},
		Cluster:  &ecsClusterName,
	})

	if err != nil {
		t.Fatal(err)
	}

	_, _ = pretty.Print(descSvcs.Services)

	if descSvcs.Services[0].DesiredCount != 1 {
		t.Fatal("service does not have correct desired count, got: ", descSvcs.Services[0].DesiredCount)
	}
}

func makediff(want interface{}, got interface{}) string {
	s := fmt.Sprintf("\nwant: %# v", pretty.Formatter(want))
	s = fmt.Sprintf("%s\ngot: %# v", s, pretty.Formatter(got))
	diffs := pretty.Diff(want, got)
	s = fmt.Sprintf("%s\ndifferences: ", s)
	for _, d := range diffs {
		s = fmt.Sprintf("%s\n  - %s", s, d)
	}
	return s
}
