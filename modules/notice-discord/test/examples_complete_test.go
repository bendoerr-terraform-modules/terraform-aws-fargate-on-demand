package test

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/bwmarrin/discordgo"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/kr/pretty"
	"k8s.io/utils/strings/slices"
	"os"
	"testing"
	"time"
)

func TestDefaults(t *testing.T) {
	t.Parallel()

	rootFolder := "../"
	terraformFolderRelativeToRoot := "examples/complete"

	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	rndns := random.UniqueId()

	discordBotAuthToken := os.Getenv("DISCORD_BOT_AUTH_TOKEN")
	discordChannelID := os.Getenv("DISCORD_CHANNEL_ID")

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		Vars: map[string]interface{}{
			"namespace":              rndns,
			"discord_bot_auth_token": discordBotAuthToken,
			"discord_channel_id":     discordChannelID,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer terraform.Destroy(t, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// Print out the output for debugging
	_, _ = pretty.Print(terraform.OutputAll(t, terraformOptions))

	// Create a channel to receive discord messages on so that we can check if the notification was sent
	discordMessageChannel := make(chan *discordgo.MessageEmbed)

	// Create a new discord bot session
	discord, err := discordgo.New("Bot " + discordBotAuthToken)
	if err != nil {
		t.Error(err)
		return
	}

	err = discord.Open()
	if err != nil {
		t.Error(err)
		return
	}

	// Make sure the bot disconnects
	defer func(discord *discordgo.Session) {
		_ = discord.Close()
	}(discord)

	// Add a discord handler for new messages and if they match the channel id put them on our channel
	discord.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		t.Log(m)

		if m.ChannelID != discordChannelID {
			return
		}

		for _, em := range m.Embeds {
			discordMessageChannel <- em
		}
	})

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

	// Send the test message
	_, err = snsSvc.Publish(context.TODO(), &sns.PublishInput{
		Message:  &testMessage,
		TopicArn: &snsTopic,
	})

	if err != nil {
		t.Error(err)
		return
	}

	// Wait to receive the test message
	timeoutTimer := time.After(time.Second * 10)
	found := false
	for !found {
		select {
		case <-timeoutTimer:
			t.Error("timeout: Failed to receive message")
			return
		case embed := <-discordMessageChannel:
			foundCount := 0

			for _, f := range embed.Fields {
				if slices.Contains([]string{testEventName, testClusterName, testServiceName, snsTopic}, f.Value) {
					foundCount++
				}
			}

			if foundCount == 0 {
				continue
			}

			if foundCount > 0 && foundCount < 4 {
				bs, _ := json.Marshal(embed)
				t.Errorf("received partial message: %s", string(bs))
				return
			}

			found = true
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
