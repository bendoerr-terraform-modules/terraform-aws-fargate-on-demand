package test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// TestDefaults applies the complete example, publishes a task-state event to the
// SNS topic, then reads the committed state file back from the sandbox GitHub
// repo and asserts the emitting service's entry was upserted with the expected
// status. The state file lives at a per-run unique path and is deleted at the
// end, so concurrent/repeated runs never collide and nothing is left behind --
// the GitHub twin of the disposable sandbox AWS account.
//
// Driven by CI secrets (see test.yml). Skips locally when unset:
//   - GITHUB_STATUS_REPO   e.g. "bendoerr-terraform-modules/notice-github-sandbox"
//   - NOTICE_GITHUB_TOKEN  fine-grained PAT, contents:write on that repo only
func TestDefaults(t *testing.T) {
	t.Parallel()

	githubRepo := os.Getenv("GITHUB_STATUS_REPO")
	githubToken := os.Getenv("NOTICE_GITHUB_TOKEN")
	if githubRepo == "" || githubToken == "" {
		t.Skip("set GITHUB_STATUS_REPO and NOTICE_GITHUB_TOKEN to run this test")
	}

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"
	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueId()
	// Unique, namespaced path per run so parallel/repeated runs never collide.
	stateFilePath := fmt.Sprintf("runs/%s.json", strings.ToLower(rndns))

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace":       rndns,
			"github_token":    githubToken,
			"github_repo":     githubRepo,
			"state_file_path": stateFilePath,
		},
	}

	// Always clean up: destroy AWS resources AND delete the state file we wrote.
	defer deleteStateFile(t, githubRepo, githubToken, stateFilePath)
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	snsTopic := terraform.Output(t, terraformOptions, "sns_topic")

	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("us-east-1"))
	if err != nil {
		t.Fatal(err)
	}
	snsSvc := sns.NewFromConfig(cfg)

	testClusterName := random.UniqueId()
	testServiceName := random.UniqueId()
	testEventName := "active"

	testEvent := map[string]string{
		"Event":   testEventName,
		"Topic":   snsTopic,
		"Cluster": testClusterName,
		"Service": testServiceName,
	}
	testMessageBytes, err := json.Marshal(testEvent)
	if err != nil {
		t.Fatal(err)
	}
	testMessage := string(testMessageBytes)

	if _, err = snsSvc.Publish(context.TODO(), &sns.PublishInput{
		Message:  &testMessage,
		TopicArn: &snsTopic,
	}); err != nil {
		t.Fatal(err)
	}

	// Poll the state file until our service entry shows up (the Lambda commits
	// asynchronously after the SNS delivery).
	deadline := time.After(90 * time.Second)
	for {
		select {
		case <-deadline:
			t.Fatalf("timeout: service %q never appeared in %s", testServiceName, stateFilePath)
		case <-time.After(5 * time.Second):
			doc, _, err := fetchState(githubRepo, githubToken, stateFilePath)
			if err != nil {
				t.Logf("fetch state (not ready yet): %v", err)
				continue
			}
			svc, ok := doc.Services[testServiceName]
			if !ok {
				continue
			}
			if svc.Status != testEventName {
				t.Fatalf("status = %q, want %q", svc.Status, testEventName)
			}
			if svc.Cluster != testClusterName {
				t.Fatalf("cluster = %q, want %q", svc.Cluster, testClusterName)
			}
			if doc.SchemaVersion != 1 {
				t.Fatalf("schema_version = %d, want 1", doc.SchemaVersion)
			}
			return
		}
	}
}

type stateDoc struct {
	SchemaVersion int                       `json:"schema_version"`
	GeneratedAt   string                    `json:"generated_at"`
	Services      map[string]stateServiceEn `json:"services"`
}

type stateServiceEn struct {
	Cluster   string `json:"cluster"`
	AppName   string `json:"app_name"`
	URL       string `json:"url"`
	Status    string `json:"status"`
	UpdatedAt string `json:"updated_at"`
}

func ghRequest(method, repo, path, token string, body []byte) (*http.Response, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/contents/%s", repo, path)
	var rdr *bytes.Reader
	if body != nil {
		rdr = bytes.NewReader(body)
	} else {
		rdr = bytes.NewReader(nil)
	}
	req, err := http.NewRequest(method, url, rdr)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	return http.DefaultClient.Do(req)
}

// fetchState returns the parsed doc and the blob sha (needed for deletion).
func fetchState(repo, token, path string) (*stateDoc, string, error) {
	res, err := ghRequest(http.MethodGet, repo, path, token, nil)
	if err != nil {
		return nil, "", err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("github contents GET %s: HTTP %d", path, res.StatusCode)
	}

	var payload struct {
		Content string `json:"content"`
		SHA     string `json:"sha"`
	}
	if err := json.NewDecoder(res.Body).Decode(&payload); err != nil {
		return nil, "", err
	}
	// The contents API wraps base64 at 76 columns with newlines; strip them.
	clean := strings.NewReplacer("\n", "", "\r", "").Replace(payload.Content)
	raw, err := base64.StdEncoding.DecodeString(clean)
	if err != nil {
		return nil, "", err
	}

	var doc stateDoc
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, "", err
	}
	return &doc, payload.SHA, nil
}

// deleteStateFile removes the per-run state file so the sandbox repo stays clean.
// Best-effort: logs but does not fail the test if the file was never created.
func deleteStateFile(t *testing.T, repo, token, path string) {
	_, sha, err := fetchState(repo, token, path)
	if err != nil {
		t.Logf("cleanup: nothing to delete at %s (%v)", path, err)
		return
	}
	body, _ := json.Marshal(map[string]string{
		"message": "chore(test): clean up " + path,
		"sha":     sha,
		"branch":  "main",
	})
	res, err := ghRequest(http.MethodDelete, repo, path, token, body)
	if err != nil {
		t.Logf("cleanup: delete %s failed: %v", path, err)
		return
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Logf("cleanup: delete %s returned HTTP %d", path, res.StatusCode)
	}
}
