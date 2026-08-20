package test_test

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/kr/pretty"
)

func TestDefaults(t *testing.T) {
	t.Parallel()

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueID()

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace": rndns,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer terraform.DestroyContext(t, context.Background(), terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApplyContext(t, context.Background(), terraformOptions)

	// Print out the output for debugging
	_, _ = pretty.Print(terraform.OutputAllContext(t, context.Background(), terraformOptions))

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
	snsTopic := terraform.OutputContext(t, context.Background(), terraformOptions, "sns_topic")
	paramName := terraform.OutputContext(t, context.Background(), terraformOptions, "parameter_name")

	// New SNS AWS Client
	snsSvc := sns.NewFromConfig(cfg)

	// Create an event message
	testClusterName := random.UniqueID()
	testServiceName := random.UniqueID()
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
	var lastErr error
	timeoutTimer := time.After(time.Second * 60)
	found := false
	for !found {
		select {
		case <-timeoutTimer:
			t.Errorf(
				"timeout: Failed to valid state (last poll error: %v), found: \n%s",
				lastErr, makediff(testEvent, stateValue),
			)
			return
		default:
			out, getErr := ssmSvc.GetParameter(context.TODO(), &ssm.GetParameterInput{Name: &paramName})
			if getErr != nil {
				// Transient SSM errors (throttling, 5xx) are what the 60s poll budget
				// exists to absorb — only the timeout arm may fail the test, and it
				// reports the last error so a persistent failure (IAM, bad name) is
				// the headline, not buried in retry logs.
				lastErr = getErr
				t.Logf("GetParameter error (will retry): %v", getErr)
				time.Sleep(time.Second)
				continue
			}
			lastErr = nil

			v := out.Parameter.Value
			t.Log("ssm parameter value: " + *v)

			// Fresh map every poll: json.Unmarshal MERGES into an existing map,
			// so a ghost key seen once would poison DeepEqual forever.
			stateValue = map[string]string{}
			err = json.Unmarshal([]byte(*v), &stateValue)
			if err != nil {
				t.Error(err)
				return
			}

			if reflect.DeepEqual(testEvent, stateValue) {
				found = true
				continue
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
