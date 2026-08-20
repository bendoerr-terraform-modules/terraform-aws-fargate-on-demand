package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestDefaultsDisabled(t *testing.T) {
	t.Parallel()

	// The example sources ../../../persistence, so the copied tree must be the
	// repo root or that relative path dangles in the temp dir.
	rootFolder := "../../../"
	terraformFolderRelativeToRoot := "modules/efs-access/examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(
		t, rootFolder, terraformFolderRelativeToRoot,
	)

	rndns := random.UniqueId()

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace": rndns,
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	outputs := terraform.OutputAll(t, terraformOptions)

	// Example defaults keep the instance and bucket off: those outputs must be
	// null/empty, while the mount_path passthrough must be a non-empty string.
	for _, key := range []string{"instance_id", "connect_command", "transfer_bucket"} {
		if v, ok := outputs[key]; ok && v != nil && v != "" {
			t.Errorf("output %q should be null with example defaults, got %#v", key, v)
		}
	}
	mp, ok := outputs["mount_path"].(string)
	if !ok || mp == "" {
		t.Errorf("output mount_path should be a non-empty string, got %#v", outputs["mount_path"])
	}
}
