package test_test

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/backup"
	backuptypes "github.com/aws/aws-sdk-go-v2/service/backup/types"
	"github.com/aws/aws-sdk-go-v2/service/efs"
	efstypes "github.com/aws/aws-sdk-go-v2/service/efs/types"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// wantOutputKeys returns the example's full output set when
// backup_enabled = true.
func wantOutputKeys() []string {
	return []string{
		"name", "file_system_id", "access_point_id", "mount_path",
		"access_policy_arn", "access_security_group", "owner_gid", "owner_uid",
		"backup_vault_arn", "backup_plan_id",
	}
}

// wantOutputKeysBackupDisabled returns the example's output set when
// backup_enabled = false: backup_vault_arn and backup_plan_id are null root
// outputs, and Terraform drops null root outputs from state/`output -json`
// (see modules/efs-access/test/examples_complete_test.go), so they are
// absent rather than present-with-null.
func wantOutputKeysBackupDisabled() []string {
	return []string{
		"name", "file_system_id", "access_point_id", "mount_path",
		"access_policy_arn", "access_security_group", "owner_gid", "owner_uid",
	}
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

// isBackupResourceNotFound reports whether err is a
// backuptypes.ResourceNotFoundException: the vault, or a recovery point
// inside it, is already gone. That's success for draining purposes, not a
// retryable failure.
func isBackupResourceNotFound(err error) bool {
	var nfe *backuptypes.ResourceNotFoundException
	return errors.As(err, &nfe)
}

// deleteRecoveryPoint deletes one recovery point, treating "already gone"
// (ResourceNotFoundException) as success rather than an error.
func deleteRecoveryPoint(
	ctx context.Context, backupClient *backup.Client, vaultName string, recoveryPointArn *string,
) error {
	_, err := backupClient.DeleteRecoveryPoint(ctx, &backup.DeleteRecoveryPointInput{
		BackupVaultName:  &vaultName,
		RecoveryPointArn: recoveryPointArn,
	})
	if err != nil && !isBackupResourceNotFound(err) {
		return fmt.Errorf("DeleteRecoveryPoint(%s): %w", *recoveryPointArn, err)
	}
	return nil
}

// drainBackupVaultOnce makes one full pass (all pages) over vaultName's
// recovery points and deletes each one, returning how many were seen. A
// vault that no longer exists counts as already drained (0, nil).
func drainBackupVaultOnce(ctx context.Context, backupClient *backup.Client, vaultName string) (int, error) {
	seen := 0
	paginator := backup.NewListRecoveryPointsByBackupVaultPaginator(
		backupClient, &backup.ListRecoveryPointsByBackupVaultInput{BackupVaultName: &vaultName},
	)
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			if isBackupResourceNotFound(err) {
				return 0, nil
			}
			return 0, err
		}
		for _, rp := range page.RecoveryPoints {
			if rp.RecoveryPointArn == nil {
				continue
			}
			if delErr := deleteRecoveryPoint(ctx, backupClient, vaultName, rp.RecoveryPointArn); delErr != nil {
				return 0, delErr
			}
			seen++
		}
	}
	return seen, nil
}

// emptyBackupVault deletes every recovery point in vaultName and waits until
// the vault reports none left. The example's daily backup rule can fire
// while a test is mid-run, landing a new recovery point between apply and
// the deferred `terraform destroy`; AWS Backup refuses to delete a vault
// that still holds a recovery point, which would otherwise fail cleanup. A
// vault that's already gone, or a recovery point that's already gone by the
// time we try to delete it, counts as drained rather than an error.
func emptyBackupVault(ctx context.Context, t *testing.T, backupClient *backup.Client, vaultName string) {
	t.Helper()

	description := fmt.Sprintf("empty backup vault %s", vaultName)
	_, err := retry.DoWithRetryContextE(t, ctx, description, 10, 15*time.Second, func() (string, error) {
		seen, err := drainBackupVaultOnce(ctx, backupClient, vaultName)
		if err != nil {
			return "", err
		}
		if seen == 0 {
			return "", nil
		}
		return "", fmt.Errorf("backup vault %s still has %d recovery point(s) pending deletion", vaultName, seen)
	})
	if err != nil {
		t.Errorf("could not empty backup vault %s before destroy: %v", vaultName, err)
	}
}

// assertFileSystemElastic asserts throughput_mode = "elastic" (the module's
// default) is in effect on the file system.
func assertFileSystemElastic(ctx context.Context, t *testing.T, efsClient *efs.Client, fileSystemID string) {
	t.Helper()
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
		t.Errorf(
			"throughput_mode should be %q, got %q",
			efstypes.ThroughputModeElastic, fsOut.FileSystems[0].ThroughputMode,
		)
	}
}

// assertBackupVaultExists asserts the vault named vaultName exists and its
// ARN matches wantArn.
func assertBackupVaultExists(
	ctx context.Context, t *testing.T, backupClient *backup.Client, vaultName, wantArn string,
) {
	t.Helper()
	vaultOut, err := backupClient.DescribeBackupVault(ctx, &backup.DescribeBackupVaultInput{
		BackupVaultName: &vaultName,
	})
	if err != nil {
		t.Fatalf("DescribeBackupVault(%s): %v", vaultName, err)
	}
	if vaultOut.BackupVaultArn == nil || *vaultOut.BackupVaultArn != wantArn {
		t.Errorf("backup vault ARN should be %s, got %v", wantArn, vaultOut.BackupVaultArn)
	}
}

// assertBackupPlanSchedule asserts the plan has exactly one rule with the
// §5.1 daily schedule targeting vaultName and the module default retention.
func assertBackupPlanSchedule(
	ctx context.Context,
	t *testing.T,
	backupClient *backup.Client,
	backupPlanID, vaultName string,
) {
	t.Helper()
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
	if rule.Lifecycle == nil || rule.Lifecycle.DeleteAfterDays == nil ||
		*rule.Lifecycle.DeleteAfterDays != wantRetention {
		t.Errorf("backup rule delete_after should be %d days, got %v", wantRetention, rule.Lifecycle)
	}
}

// assertBackupSelectionTargetsFileSystem asserts the plan's single selection
// includes the file system's ARN and carries a non-empty IAM role.
func assertBackupSelectionTargetsFileSystem(
	ctx context.Context, t *testing.T,
	backupClient *backup.Client, efsClient *efs.Client,
	backupPlanID, fileSystemID string,
) {
	t.Helper()
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
		t.Errorf(
			"backup selection resources %v should contain the file system ARN %s",
			getSelOut.BackupSelection.Resources, fileSystemArn,
		)
	}
	if getSelOut.BackupSelection.IamRoleArn == nil || *getSelOut.BackupSelection.IamRoleArn == "" {
		t.Error("backup selection should have a non-empty IAM role ARN")
	}
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

	rndns := random.UniqueID()

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
	assertOutputKeySet(t, outputs, wantOutputKeys())

	fileSystemID := outputString(t, outputs, "file_system_id")
	backupVaultArn := outputString(t, outputs, "backup_vault_arn")
	backupPlanID := outputString(t, outputs, "backup_plan_id")

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		t.Fatal(err)
	}

	efsClient := efs.NewFromConfig(cfg)
	assertFileSystemElastic(ctx, t, efsClient, fileSystemID)

	backupClient := backup.NewFromConfig(cfg)
	vaultName := backupVaultNameFromArn(t, backupVaultArn)

	// Declared after the destroy defer above, so per Go's LIFO defer order it
	// runs first: drain the vault's recovery points before destroy runs.
	defer emptyBackupVault(ctx, t, backupClient, vaultName)

	assertBackupVaultExists(ctx, t, backupClient, vaultName, backupVaultArn)
	assertBackupPlanSchedule(ctx, t, backupClient, backupPlanID, vaultName)
	assertBackupSelectionTargetsFileSystem(ctx, t, backupClient, efsClient, backupPlanID, fileSystemID)
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

	rndns := random.UniqueID()

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
	assertOutputKeySet(t, outputs, wantOutputKeysBackupDisabled())

	if _, ok := outputs["backup_vault_arn"]; ok {
		t.Errorf("backup_vault_arn should be absent when backup_enabled = false, got %#v", outputs["backup_vault_arn"])
	}
	if _, ok := outputs["backup_plan_id"]; ok {
		t.Errorf("backup_plan_id should be absent when backup_enabled = false, got %#v", outputs["backup_plan_id"])
	}

	state := terraform.RunTerraformCommandContext(t, ctx, terraformOptions, "state", "list")
	for _, line := range strings.Split(state, "\n") {
		if strings.Contains(line, "aws_backup") {
			t.Errorf("no aws_backup_* resource should be in state when backup_enabled = false, found %q", line)
		}
	}
}
