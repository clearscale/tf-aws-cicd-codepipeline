package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/codepipeline"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

/**
 * Using default variables
 * TODO: Test the rest of the values
 */
func TestTerraformCodePipeline(t *testing.T) {
	uniqueId := random.UniqueId()
	region := "us-west-1"
	pipelineName := fmt.Sprintf("testing-%s", strings.ToLower(uniqueId))
	repoName := fmt.Sprintf("my-codecommit-repo%s", strings.ToLower(uniqueId))
	s3_bucket := strings.ToLower(fmt.Sprintf("cs-testing-artifacts-%s", uniqueId))

	// Construct the terraform options with default retryable errors to handle the most common
	// retryable errors in terraform testing.
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Set the path to the Terraform code that will be tested.
		TerraformDir: "../iam",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"artifact_stores": []map[string]interface{}{
				{
					"location": s3_bucket,
				},
			},
			"repo": map[string]interface{}{
				"action": map[string]interface{}{
					"configuration": map[string]interface{}{
						"RepositoryName": repoName,
					},
				},
			},
			"stages": []map[string]interface{}{
				{
					"name": "CodeBuildProjectName",
					"action": map[string]interface{}{
						"configuration": map[string]interface{}{},
					},
				},
			},
		},
	})

	// Clean up resources with "terraform destroy" at the end of the test.
	defer terraform.Destroy(t, terraformOptions)

	// Run "terraform init" and "terraform apply". Fail the test if there are any errors.
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the value of an output variable
	output := terraform.OutputMap(t, terraformOptions, "role")

	// Dash notation
	expectedRoleName := fmt.Sprintf("CsPmod.Shared.Uswest1.Dev.CodePipeline.MyCodecommitRepo%s",
		strings.ToLower(uniqueId),
	)
	assert.Equal(t, expectedRoleName, output["name"])

	terraformOptions = terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../",
		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"name": pipelineName,
			"artifact_stores": []map[string]interface{}{
				{
					"location": s3_bucket,
				},
			},
			"repo": map[string]interface{}{
				"action": map[string]interface{}{
					"configuration": map[string]interface{}{
						"RepositoryName": repoName,
					},
				},
			},
			"stages": []map[string]interface{}{
				{
					"name": "CodeBuildProjectName",
					"action": map[string]interface{}{
						"configuration": map[string]interface{}{},
					},
				},
			},
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get the name of the CodePipeline from Terraform output
	codePipelineName := terraform.Output(t, terraformOptions, "name")

	// Create an AWS session
	awsSession, err := session.NewSessionWithOptions(session.Options{
		Profile:           "default",
		Config:            aws.Config{Region: aws.String(region)},
		SharedConfigState: session.SharedConfigEnable,
	})
	if err != nil {
		t.Fatalf("Failed to create AWS session: %v", err)
	}

	// Create a CodePipeline client
	codePipelineClient := codepipeline.New(awsSession)

	// Call the CodePipeline GetPipeline API
	_, err = codePipelineClient.GetPipeline(&codepipeline.GetPipelineInput{
		Name: aws.String(codePipelineName),
	})

	// Assert that there was no error (i.e., the pipeline exists)
	assert.NoError(t, err, "CodePipeline does not exist")
}
