# Terraform AWS/CICD CodePipeline

Set up and manage an [AWS CodePipeline](https://aws.amazon.com/codepipeline/) to facilitate  [Continuous Integration](https://en.wikipedia.org/wiki/Continuous_integration) and Continuous [Deployments](https://en.wikipedia.org/wiki/Continuous_deployment)/[Delivery](https://en.wikipedia.org/wiki/Continuous_delivery) (CI/CD). Use `var.stages` to define different build and deployment processes. Currently, [AWS CodeBuild](https://aws.amazon.com/codebuild/) is the sole stage provider supported.

## Prerequisites

- Using the same parameters, deploy the [IAM role and policies](./iam/README.md) for this module prior to deploying these resources.
- Create an S3 bucket for the pipeline artifacts and pass the name to the module as `var.artifact_stores[{location="S3BUCKET"}]`

## Usage

Include the module in your Terraformcode

```terraform
module "codepipeline" {
  source    = "https://github.com/clearscale/tf-aws-cicd-codepipeline.git"

  accounts = [
    { name = "shared", provider = "aws", key = "shared"}
  ]

  prefix   = "ex"
  client   = "example"
  project  = "aws"
  env      = "dev"
  region   = "us-east-1"
  name     = "testing"

  artifact_stores = [{
    location="my-s3-bucket-for-artifact-storage"
  }]
  repo = {
    action = {
        configuration="my-codecommit-repo"
    }
  }
  stages = [{
    name   = "CodeBuildProjectName"
    action = {
        configuration = {}
    }
  }]
}
```

## Plan

```bash
terraform plan -var='name=testing' -var='artifact_stores=[{location="my-s3-bucket"}]' -var='repo={action={configuration={RepositoryName="my-codecommit-repo"}}}' -var='stages=[{name="CodeBuildProjectName",action={configuration={}}}]'
```

## Apply

```bash
terraform apply -var='name=testing' -var='artifact_stores=[{location="my-s3-bucket"}]' -var='repo={action={configuration={RepositoryName="my-codecommit-repo"}}}' -var='stages=[{name="CodeBuildProjectName",action={configuration={}}}]'
```

## Destroy

```bash
terraform destroy -var='name=testing' -var='artifact_stores=[{location="my-s3-bucket"}]' -var='repo={action={configuration={RepositoryName="my-codecommit-repo"}}}' -var='stages=[{name="CodeBuildProjectName",action={configuration={}}}]'
```