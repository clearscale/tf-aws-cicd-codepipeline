# Terraform AWS/CICD CodePipeline IAM

Create and manage IAM roles and policies for CodePipeline.

## Usage

Include the module in your Terraformcode

```terraform
module "codepipeline_iam" {
  source    = "https://github.com/clearscale/tf-aws-cicd-codepipeline.git//iam"

  accounts = [
    { name = "shared", provider = "aws", key = "shared"}
  ]

  prefix   = "ex"
  client   = "example"
  project  = "aws"
  env      = "dev"
  region   = "us-east-1"
  name     = "codepipeline"

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
terraform plan -var='artifact_stores=[{location="my-s3-bucket"}]' -var='repo={action={configuration={RepositoryName="my-codecommit-repo"}}}' -var='stages=[{name="CodeBuildProjectName",action={configuration={}}}]'
```

## Apply

```bash
terraform apply -var='artifact_stores=[{location="my-s3-bucket"}]' -var='repo={action={configuration={RepositoryName="my-codecommit-repo"}}}' -var='stages=[{name="CodeBuildProjectName",action={configuration={}}}]'
```

## Destroy

```bash
terraform destroy -var='artifact_stores=[{location="my-s3-bucket"}]' -var='repo={action={configuration={RepositoryName="my-codecommit-repo"}}}' -var='stages=[{name="CodeBuildProjectName",action={configuration={}}}]'
```