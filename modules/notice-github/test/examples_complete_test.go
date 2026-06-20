package test

import (
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
// SNS topic, then reads state.json back from the target GitHub repo and asserts
// the emitting service's entry was upserted with the expected status.
//
// Requires (not wired into the CI test matrix yet -- costs a live sandbox apply
// and needs repo/token secrets):
//   - GITHUB_STATUS_REPO  e.g. "bendoerr/status-sandbox"
//   - GITHUB_TOKEN        fine-grained PAT, contents:write on that repo
func TestDefaults(t *testing.T) {
	t.Parallel()

	githubRepo := os.Getenv("GITHUB_STATUS_REPO")
	githubToken := os.Getenv("GITHUB_TOKEN")
	if githubRepo == "" || githubToken == "" {
		t.Skip("set GITHUB_STATUS_REPO and GITHUB_TOKEN to run this test")
	}

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"
	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueId()

	terraformOptions := &terraform.Options{
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace":    rndns,
			"github_token": githubToken,
			"github_repo":  githubRepo,
		},
	}

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

	// Poll state.json until our service entry shows up (the Lambda commits async).
	deadline := time.After(60 * time.Second)
	for {
		select {
		case <-deadline:
			t.Fatalf("timeout: service %q never appeared in state.json", testServiceName)
		case <-time.After(5 * time.Second):
			state, err := fetchState(githubRepo, githubToken)
			if err != nil {
				t.Logf("fetch state: %v", err)
				continue
			}
			svc, ok := state.Services[testServiceName]
			if !ok {
				continue
			}
			if svc.Status != testEventName {
				t.Fatalf("status = %q, want %q", svc.Status, testEventName)
			}
			if svc.Cluster != testClusterName {
				t.Fatalf("cluster = %q, want %q", svc.Cluster, testClusterName)
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

func fetchState(repo, token string) (*stateDoc, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/contents/state.json", repo)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("github contents API: HTTP %d", res.StatusCode)
	}

	var payload struct {
		Content string `json:"content"`
	}
	if err := json.NewDecoder(res.Body).Decode(&payload); err != nil {
		return nil, err
	}
	// The GitHub contents API wraps base64 content at 76 columns with newlines,
	// which the standard decoder rejects -- strip whitespace first.
	clean := strings.NewReplacer("\n", "", "\r", "").Replace(payload.Content)
	raw, err := base64.StdEncoding.DecodeString(clean)
	if err != nil {
		return nil, err
	}

	var doc stateDoc
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, err
	}
	return &doc, nil
}
