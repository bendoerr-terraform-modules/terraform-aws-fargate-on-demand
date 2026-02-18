package test

import (
	"context"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials/stscreds"
	"github.com/aws/aws-sdk-go-v2/service/route53"
	"github.com/aws/aws-sdk-go-v2/service/route53/types"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/kr/pretty"
	"strings"
	"testing"
	"time"
)

func TestDefaults(t *testing.T) {
	t.Parallel()

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	// Will be used in dns names, need to normalize to lower case letters
	rndns := strings.ToLower(random.UniqueId())

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

	// Print the output
	_, _ = pretty.Println(terraform.OutputAll(t, terraformOptions))

	// Get the test role
	testRecordControlRoleArn := terraform.Output(t, terraformOptions, "test_record_control_role_arn")
	testZoneId := terraform.Output(t, terraformOptions, "test_route53_zone_id")
	testZoneName := terraform.Output(t, terraformOptions, "test_route53_zone_name")
	testRecordName := terraform.Output(t, terraformOptions, "record_name")

	// AWS Session
	cfg, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithRegion("us-east-1"),
	)

	if err != nil {
		t.Error(err)
		return
	}

	// Create an initial record that we can verify we get denied
	unchangeableRecord := "unchangeable." + testZoneName

	route53svc := route53.NewFromConfig(cfg)
	_, err = route53svc.ChangeResourceRecordSets(context.TODO(), &route53.ChangeResourceRecordSetsInput{
		ChangeBatch: &types.ChangeBatch{
			Changes: []types.Change{{
				Action: "CREATE",
				ResourceRecordSet: &types.ResourceRecordSet{
					Name: &unchangeableRecord,
					Type: "A",
					ResourceRecords: []types.ResourceRecord{{
						Value: aws.String("1.1.1.1"),
					}},
					TTL: aws.Int64(60),
				},
			}},
		},
		HostedZoneId: &testZoneId,
	})

	if err != nil {
		t.Error(err)
		return
	}

	// Ensure the record is cleaned up
	defer func(route53svc *route53.Client) {
		_, _ = route53svc.ChangeResourceRecordSets(context.TODO(), &route53.ChangeResourceRecordSetsInput{
			ChangeBatch: &types.ChangeBatch{
				Changes: []types.Change{{
					Action: "DELETE",
					ResourceRecordSet: &types.ResourceRecordSet{
						Name: &unchangeableRecord,
						Type: "A",
						ResourceRecords: []types.ResourceRecord{{
							Value: aws.String("1.1.1.1"),
						}},
						TTL: aws.Int64(60),
					},
				}},
			},
			HostedZoneId: &testZoneId,
		})
	}(route53svc)

	// Trying to use the new policy too fast causes issues, give it a sec
	time.Sleep(15 * time.Second)

	// Assume Role AWS Session
	cfg2, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithRegion("us-east-1"),
	)

	if err != nil {
		t.Error(err)
		return
	}

	appCreds := stscreds.NewAssumeRoleProvider(sts.NewFromConfig(cfg2), testRecordControlRoleArn)
	_, err = appCreds.Retrieve(context.TODO())

	if err != nil {
		t.Error(err)
		return
	}

	cfg2.Credentials = appCreds

	route53svc2 := route53.NewFromConfig(cfg2)

	// Validate that we can get the zone info
	_, err = route53svc2.GetHostedZone(context.TODO(), &route53.GetHostedZoneInput{Id: &testZoneId})

	if err != nil {
		t.Error(err)
		return
	}

	// Validate that we can list the zone records
	record_sets, err := route53svc2.ListResourceRecordSets(context.TODO(), &route53.ListResourceRecordSetsInput{
		HostedZoneId: &testZoneId,
	})

	if err != nil {
		t.Error(err)
		return
	}

	found := false
	for _, rs := range record_sets.ResourceRecordSets {
		if strings.TrimRight(*rs.Name, ".") == testRecordName {
			found = true
			break
		}
	}

	if !found {
		t.Error("Failed to find record name")
		return
	}

	// Validate that we can update the record
	_, err = route53svc2.ChangeResourceRecordSets(context.TODO(), &route53.ChangeResourceRecordSetsInput{
		ChangeBatch: &types.ChangeBatch{
			Changes: []types.Change{{
				Action: "UPSERT",
				ResourceRecordSet: &types.ResourceRecordSet{
					Name: &testRecordName,
					Type: "A",
					ResourceRecords: []types.ResourceRecord{{
						Value: aws.String("8.8.8.8"),
					}},
					TTL: aws.Int64(60),
				},
			}},
		},
		HostedZoneId: &testZoneId,
	})

	if err != nil {
		t.Error(err)
		return
	}

	// Validate that we can NOT update the other record
	_, err = route53svc2.ChangeResourceRecordSets(context.TODO(), &route53.ChangeResourceRecordSetsInput{
		ChangeBatch: &types.ChangeBatch{
			Changes: []types.Change{{
				Action: "UPSERT",
				ResourceRecordSet: &types.ResourceRecordSet{
					Name: &unchangeableRecord,
					Type: "A",
					ResourceRecords: []types.ResourceRecord{{
						Value: aws.String("8.8.8.8"),
					}},
					TTL: aws.Int64(60),
				},
			}},
		},
		HostedZoneId: &testZoneId,
	})

	if err == nil {
		t.Error("failed to error")
		return
	}
}
