package test

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/kr/pretty"
	"reflect"
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

	// Print out the output for debugging
	_, _ = pretty.Print(terraform.OutputAll(t, terraformOptions))

	// AWS Session
	cfg, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithRegion("us-east-1"),
	)

	if err != nil {
		t.Error(err)
		return
	}

	// Get the SNS Topic so that we can send a message
	snsTopic := terraform.Output(t, terraformOptions, "sns_topic")
	paramName := terraform.Output(t, terraformOptions, "parameter_name")

	// New SNS AWS Client
	snsSvc := sns.NewFromConfig(cfg)

	// Create an event message
	testClusterName := random.UniqueId()
	testServiceName := random.UniqueId()
	testEventName := random.RandomString([]string{"start", "active", "inactive", "stop", "foobar"})

	testEvent := map[string]string{
		"Event":   testEventName,
		"Topic":   snsTopic,
		"Cluster": testClusterName,
		"Service": testServiceName,
	}
	testMessageBytes, err := json.Marshal(testEvent)
	if err != nil {
		t.Error(err)
		return
	}

	testMessage := string(testMessageBytes)
	t.Log(testMessage)

	// Send the test message
	_, err = snsSvc.Publish(context.TODO(), &sns.PublishInput{
		Message:  &testMessage,
		TopicArn: &snsTopic,
	})

	if err != nil {
		t.Error(err)
		return
	}

	// New SSM AWS Client
	ssmSvc := ssm.NewFromConfig(cfg)

	// Wait to receive the test message
	stateValue := map[string]string{}
	timeoutTimer := time.After(time.Second * 10)
	found := false
	for !found {
		select {
		case <-timeoutTimer:
			t.Errorf("timeout: Failed to valid state, found: \n%s", makediff(testEvent, stateValue))
			return
		default:
			out, err := ssmSvc.GetParameter(context.TODO(), &ssm.GetParameterInput{Name: &paramName})
			if err != nil {
				t.Error(err)
				return
			}

			v := out.Parameter.Value
			t.Log("ssm parameter value: " + *v)

			err = json.Unmarshal([]byte(*v), &stateValue)
			if err != nil {
				t.Error(err)
				return
			}

			if reflect.DeepEqual(testEvent, stateValue) {
				found = true
			}

			time.Sleep(time.Second)
		}
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
