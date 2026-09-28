package test

import (
	"context"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/backup"
	"github.com/aws/aws-sdk-go-v2/service/efs"
	efstypes "github.com/aws/aws-sdk-go-v2/service/efs/types"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// The example's full output set when backup_enabled = true.
var wantOutputKeys = []string{
	"name", "file_system_id", "access_point_id", "mount_path",
	"access_policy_arn", "access_security_group", "owner_gid", "owner_uid",
	"backup_vault_arn", "backup_plan_id",
}

// The example's output set when backup_enabled = false: backup_vault_arn and
// backup_plan_id are null root outputs, and Terraform drops null root
// outputs from state/`output -json` (see
// modules/efs-access/test/examples_complete_test.go), so they are absent
// rather than present-with-null.
var wantOutputKeysBackupDisabled = []string{
	"name", "file_system_id", "access_point_id", "mount_path",
	"access_policy_arn", "access_security_group", "owner_gid", "owner_uid",
}

func assertOutputKeySet(t *testing.T, outputs map[string]interface{}, wantKeys []string) {
	t.Helper()
	want := append([]string(nil), wantKeys...)
	sort.Strings(want)
	got := make([]string, 0, len(outputs))
	for k := range outputs {
		got = append(got, k)
	}
	sort.Strings(got)
	if !reflect.DeepEqual(want, got) {
		t.Fatalf("output key set should be %v, got %v", want, got)
	}
}

func outputString(t *testing.T, outputs map[string]interface{}, key string) string {
	t.Helper()
	v, ok := outputs[key].(string)
	if !ok || v == "" {
		t.Fatalf("output %q should be a non-empty string, got %#v", key, outputs[key])
	}
	return v
}

// backupVaultNameFromArn extracts the vault name from
// arn:aws:backup:<region>:<account>:backup-vault:<name>.
func backupVaultNameFromArn(t *testing.T, arn string) string {
	t.Helper()
	parts := strings.Split(arn, ":")
	if len(parts) == 0 {
		t.Fatalf("could not parse backup vault name from ARN %q", arn)
	}
	return parts[len(parts)-1]
}

// TestDefaults applies the example with the module's defaults
// (backup_enabled = true, throughput_mode = elastic) and asserts, via the
// EFS and Backup APIs, that the file system uses elastic throughput and that
// the vault/plan/selection described in spec §5.1 exist with the expected
// schedule and retention.
func TestDefaults(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueId()

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace": rndns,
		},
	}

	defer terraform.DestroyContext(t, ctx, terraformOptions)
	terraform.InitAndApplyContext(t, ctx, terraformOptions)

	outputs := terraform.OutputAllContext(t, ctx, terraformOptions)
	assertOutputKeySet(t, outputs, wantOutputKeys)

	fileSystemID := outputString(t, outputs, "file_system_id")
	backupVaultArn := outputString(t, outputs, "backup_vault_arn")
	backupPlanID := outputString(t, outputs, "backup_plan_id")

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		t.Fatal(err)
	}

	// throughput_mode = "elastic" (the module's default) is in effect on the
	// file system.
	efsClient := efs.NewFromConfig(cfg)
	fsOut, err := efsClient.DescribeFileSystems(ctx, &efs.DescribeFileSystemsInput{
		FileSystemId: &fileSystemID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(fsOut.FileSystems) != 1 {
		t.Fatalf("expected exactly one file system for ID %s, got %d", fileSystemID, len(fsOut.FileSystems))
	}
	if fsOut.FileSystems[0].ThroughputMode != efstypes.ThroughputModeElastic {
		t.Errorf("throughput_mode should be %q, got %q", efstypes.ThroughputModeElastic, fsOut.FileSystems[0].ThroughputMode)
	}

	backupClient := backup.NewFromConfig(cfg)

	// Vault exists.
	vaultName := backupVaultNameFromArn(t, backupVaultArn)
	vaultOut, err := backupClient.DescribeBackupVault(ctx, &backup.DescribeBackupVaultInput{
		BackupVaultName: &vaultName,
	})
	if err != nil {
		t.Fatalf("DescribeBackupVault(%s): %v", vaultName, err)
	}
	if vaultOut.BackupVaultArn == nil || *vaultOut.BackupVaultArn != backupVaultArn {
		t.Errorf("backup vault ARN should be %s, got %v", backupVaultArn, vaultOut.BackupVaultArn)
	}

	// Plan exists with the §5.1 schedule and retention.
	planOut, err := backupClient.GetBackupPlan(ctx, &backup.GetBackupPlanInput{
		BackupPlanId: &backupPlanID,
	})
	if err != nil {
		t.Fatalf("GetBackupPlan(%s): %v", backupPlanID, err)
	}
	if planOut.BackupPlan == nil || len(planOut.BackupPlan.Rules) != 1 {
		t.Fatalf("expected exactly one backup rule, got %#v", planOut.BackupPlan)
	}
	rule := planOut.BackupPlan.Rules[0]
	wantSchedule := "cron(0 5 * * ? *)"
	if rule.ScheduleExpression == nil || *rule.ScheduleExpression != wantSchedule {
		t.Errorf("backup rule schedule should be %q, got %v", wantSchedule, rule.ScheduleExpression)
	}
	if rule.TargetBackupVaultName == nil || *rule.TargetBackupVaultName != vaultName {
		t.Errorf("backup rule target vault should be %q, got %v", vaultName, rule.TargetBackupVaultName)
	}
	var wantRetention int64 = 14 // module default backup_retention_days
	if rule.Lifecycle == nil || rule.Lifecycle.DeleteAfterDays == nil || *rule.Lifecycle.DeleteAfterDays != wantRetention {
		t.Errorf("backup rule delete_after should be %d days, got %v", wantRetention, rule.Lifecycle)
	}

	// Selection targets the file system.
	selOut, err := backupClient.ListBackupSelections(ctx, &backup.ListBackupSelectionsInput{
		BackupPlanId: &backupPlanID,
	})
	if err != nil {
		t.Fatalf("ListBackupSelections(%s): %v", backupPlanID, err)
	}
	if len(selOut.BackupSelectionsList) != 1 {
		t.Fatalf("expected exactly one backup selection, got %d", len(selOut.BackupSelectionsList))
	}
	selectionID := selOut.BackupSelectionsList[0].SelectionId

	getSelOut, err := backupClient.GetBackupSelection(ctx, &backup.GetBackupSelectionInput{
		BackupPlanId: &backupPlanID,
		SelectionId:  selectionID,
	})
	if err != nil {
		t.Fatalf("GetBackupSelection(%s): %v", *selectionID, err)
	}
	if getSelOut.BackupSelection == nil {
		t.Fatal("GetBackupSelection returned a nil selection")
	}

	fsArnOut, err := efsClient.DescribeFileSystems(ctx, &efs.DescribeFileSystemsInput{FileSystemId: &fileSystemID})
	if err != nil {
		t.Fatal(err)
	}
	if len(fsArnOut.FileSystems) != 1 || fsArnOut.FileSystems[0].FileSystemArn == nil {
		t.Fatalf("could not resolve the file system's ARN")
	}
	fileSystemArn := *fsArnOut.FileSystems[0].FileSystemArn

	foundResource := false
	for _, r := range getSelOut.BackupSelection.Resources {
		if r == fileSystemArn {
			foundResource = true
			break
		}
	}
	if !foundResource {
		t.Errorf("backup selection resources %v should contain the file system ARN %s", getSelOut.BackupSelection.Resources, fileSystemArn)
	}
	if getSelOut.BackupSelection.IamRoleArn == nil || *getSelOut.BackupSelection.IamRoleArn == "" {
		t.Error("backup selection should have a non-empty IAM role ARN")
	}
}

// TestBackupDisabled applies the example with backup_enabled = false and
// asserts that no backup resources are created: backup_vault_arn and
// backup_plan_id are absent from the outputs (Terraform drops null root
// outputs), and no aws_backup_* resource is in state.
func TestBackupDisabled(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueId()

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace":      rndns,
			"backup_enabled": false,
		},
	}

	defer terraform.DestroyContext(t, ctx, terraformOptions)
	terraform.InitAndApplyContext(t, ctx, terraformOptions)

	outputs := terraform.OutputAllContext(t, ctx, terraformOptions)
	assertOutputKeySet(t, outputs, wantOutputKeysBackupDisabled)

	if _, ok := outputs["backup_vault_arn"]; ok {
		t.Errorf("backup_vault_arn should be absent when backup_enabled = false, got %#v", outputs["backup_vault_arn"])
	}
	if _, ok := outputs["backup_plan_id"]; ok {
		t.Errorf("backup_plan_id should be absent when backup_enabled = false, got %#v", outputs["backup_plan_id"])
	}

	state := terraform.RunTerraformCommand(t, terraformOptions, "state", "list")
	for _, line := range strings.Split(state, "\n") {
		if strings.Contains(line, "aws_backup") {
			t.Errorf("no aws_backup_* resource should be in state when backup_enabled = false, found %q", line)
		}
	}
}
