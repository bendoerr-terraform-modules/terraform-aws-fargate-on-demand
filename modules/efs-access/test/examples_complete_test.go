package test_test

import (
	"context"
	"reflect"
	"sort"
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

	rndns := random.UniqueID()

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace": rndns,
		},
	}

	defer terraform.DestroyContext(t, context.Background(), terraformOptions)
	terraform.InitAndApplyContext(t, context.Background(), terraformOptions)

	outputs := terraform.OutputAllContext(t, context.Background(), terraformOptions)

	// With example defaults every gated output (instance_id, connect_command,
	// transfer_bucket) is null, and terraform omits null outputs from
	// `output -json` — so assert the EXACT surviving key set. Per-key absence
	// checks would pass vacuously on a typo'd or renamed key; set equality goes
	// red if a gated resource turns on (its key appears) or an output is renamed.
	wantKeys := []string{"mount_path"}
	gotKeys := make([]string, 0, len(outputs))
	for k := range outputs {
		gotKeys = append(gotKeys, k)
	}
	sort.Strings(gotKeys)
	if !reflect.DeepEqual(wantKeys, gotKeys) {
		t.Errorf("output key set with defaults should be %v, got %v", wantKeys, gotKeys)
	}
	mp, ok := outputs["mount_path"].(string)
	if !ok || mp == "" {
		t.Errorf("output mount_path should be a non-empty string, got %#v", outputs["mount_path"])
	}
}
