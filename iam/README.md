# Terraform AWS/CICD CodePipeline IAM

`NOTE:` Use [tf-aws-cicd](https://github.com/clearscale/tf-aws-cicd) instead of using this module directly.

Create and manage IAM roles and policies for CodePipeline.

## Usage

Include the module in your Terraformcode

`NOTE:` This is a unverified example. Please do not use it. Use the [tf-aws-cicd](https://github.com/clearscale/tf-aws-cicd) module instead. 

```terraform
locals {
  bucket_name = module.std.names.aws.dev.general

  # Run and replace this value with the output: aws s3api list-buckets --query Owner.ID --output text
  account_repo_canonical_id = "2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A6B7C8D9E0F1A2B3C4D5E6F7"

  repo_name = "test"
  repo_role = "arn:aws:iam::123456789012:role/CsTffwkcs.Shared.USW1.CodeCommit.Test"

  # Format for CodeBuild module
  stages = [{
    name   = "Plan"
    action = {
      provider      = "CodeBuild"
      configuration = {
        ProjectName = (
          "plan"
        )
      }
    }
    resource = {
      description = "CICDTEST: Plan project resources."
      script      = "plan.yml"
      compute = {
        compute_type = "BUILD_GENERAL1_SMALL"
        image        = "aws/codebuild/standard:6.0-22.06.30" # "ACCOUNTID.dkr.ecr.REGION.amazonaws.com/ecr-repo:latest"
        type         = "LINUX_CONTAINER"
      }
    }
  }, {
    name   = "Apply"
    action = {
      provider      = "CodeBuild"
      configuration = {
        ProjectName = (
          "apply"
        )
      }
    }
    resource = {
      description = "CICDTEST: Apply project resources."
      script      = "plan.yml"
      compute = {
        compute_type = "BUILD_GENERAL1_SMALL"
        image        = "aws/codebuild/standard:6.0-22.06.30" # "ACCOUNTID.dkr.ecr.REGION.amazonaws.com/ecr-repo:latest"
        type         = "LINUX_CONTAINER"
      }
    }
  }]

  # Convert CodeBuild module format to CodePipeline module format.
  modified_stages = [
    for stage in local.stages : merge(
      stage,
      {
        action = merge(
          stage.action,
          {
            name        = module.codebuild.name
            role_arn    = module.codebuild.role.arn
            stage_roles = module.codebuild.stage_roles
            configuration = {
              ProjectName = module.codebuild.name
            }
          }
        )
      }
    )
  ]
}

#
# Current AWS context
#
data "aws_caller_identity"   "current" {}
data "aws_canonical_user_id" "current" {}

module "std" {
  source =  "github.com/clearscale/tf-standards.git?ref=v1.0.0"

  accounts = [{
    id = "*", name = local.account.name, provider = "aws", key = "current", region = local.region.name
  }]

  prefix  = local.context.prefix
  client  = local.context.client
  project = local.context.project
  env     = local.account.name
  region  = local.region.name
  name    = "codepipeline"
  function = "test"
}

#
# Create and manage an S3 bucket for CICD pipelines.
# Cache, assets, and SCM repository files will use this bucket.
#
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.15.1"

  bucket = local.bucket_name

  versioning = {
    enabled = false
  }

  # server_side_encryption_configuration = {
  #   rule = {
  #     apply_server_side_encryption_by_default = {
  #       kms_master_key_id = module.kms.key_arn
  #       sse_algorithm     = "aws:kms"
  #     }
  #   }
  # }

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"
  attach_policy            = true
  force_destroy            = true # Allow deletion of non-empty bucket
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = [
            "ARN_CODECOMMIT_REPO" # Can be determined and entered prior to deployment using output from module.std,
            "ARN_CODEPIPELINE"    # Can be determined and entered prior to deployment using output from module.std
          ]
        },
        Action = [
          "s3:ListBucket",
          #"s3:ListBuckets",
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetLifecycleConfiguration",
          "s3:GetBucketOwnershipControls",
          "s3:GetBucketPolicy",
          "s3:GetObjectVersion",
          "s3:ListMultipartUploadParts",
          "s3:PutObjectAcl",
          "s3:PutObjectVersionAcl",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ],
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ],
        "Condition": {
          "StringEquals": {
            "aws:SourceAccount": distinct([
              data.aws_caller_identity.current.account_id,
              "123456789012", # SHARED ACCOUNT ID
            ])
          }
        }
      }
    ]
  })

  # Sometimes only explict ACL grants work for cross account setups
  # Enable cross-account support.
  acl   = null
  grant = (data.aws_canonical_user_id.current.id != local.account_repo_canonical_id ? [{
      type       = "CanonicalUser"
      permission = "FULL_CONTROL"
      id         = data.aws_canonical_user_id.current.id
    },{
      type       = "CanonicalUser"
      permission = "READ"
      id         = local.account_repo_canonical_id
    },{
      type       = "CanonicalUser"
      permission = "WRITE"
      id         = local.account_repo_canonical_id
    },{
      type       = "CanonicalUser"
      permission = "READ_ACP"
      id         = local.account_repo_canonical_id
    }
  ] : [])
}

#
# Dependency (chicken-and-egg) issue:
# The CodePipeline IAM role must be created first. 
# CodeCommit must trust CodePipeline, but AWS disallows trusting non-existent roles.
# We can, however, add non-existent ARNs to IAM policies, just not trust relationships.
#
# Thus:
#   a. Create the CodePipeline role with a generated (yet non-existent) CodeCommit ARN.
#   b. Then, establish the CodeCommit role trusting CodePipeline.
#   c. Finally, deploy the remaining resources.
#
module "codepipeline_iam" {
  source    = "github.com/clearscale/tf-aws-cicd-codepipeline.git//iam?ref=v1.0.0"

  account = {
    id = "*", name = local.account.name, provider = "aws", key = "current", region = local.region.name
  }

  prefix  = local.context.prefix
  client  = local.context.client
  project = local.context.project
  env     = local.account.name
  region  = local.region.name
  name    = "codepipeline"

  artifact_stores = [{
    type     = "S3"
    location = module.s3_bucket.s3_bucket_arn
  }]

  repo = {
    name = "Source"
    action = {
      role_arn = local.repo_role
      configuration = {
        RepositoryName  = local.repo_name
        BranchName      = "main"
        EncryptionKey   = null
      }
    }
  }

  stages = local.modified_stages
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
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.6 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_std"></a> [std](#module\_std) | github.com/clearscale/tf-standards.git | v1.0.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cb_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account"></a> [account](#input\_account) | (Optional). Cloud provider account object. | <pre>object({<br>    key      = optional(string, "current")<br>    provider = optional(string, "aws")<br>    id       = optional(string, "*") <br>    name     = string<br>    region   = optional(string, null)<br>  })</pre> | <pre>{<br>  "id": "*",<br>  "name": "shared"<br>}</pre> | no |
| <a name="input_artifact_stores"></a> [artifact\_stores](#input\_artifact\_stores) | (Required). Artifact data stores. Currently only S3 is supported and mult-region stores have not been tested. | <pre>list(object({<br>    type             = optional(string, "S3")<br>    location         = string<br>    region           = optional(string, null)<br>    encryption_key   = optional(string, null)<br>  }))</pre> | n/a | yes |
| <a name="input_client"></a> [client](#input\_client) | (Optional). Name of the client. | `string` | `"ClearScale"` | no |
| <a name="input_env"></a> [env](#input\_env) | (Optional). Name of the current environment. | `string` | `"dev"` | no |
| <a name="input_iam_service_role_policies"></a> [iam\_service\_role\_policies](#input\_iam\_service\_role\_policies) | (Optional). List of IAM policy ARNs to attach to the primary service role. | `list(string)` | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | (Optional). The name of the pipeline. | `string` | `"codepipeline"` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | (Optional). Prefix override for all generated naming conventions. | `string` | `"cs"` | no |
| <a name="input_project"></a> [project](#input\_project) | (Optional). Name of the client project. | `string` | `"pmod"` | no |
| <a name="input_region"></a> [region](#input\_region) | (Optional). AWS region. | `string` | `"us-west-1"` | no |
| <a name="input_repo"></a> [repo](#input\_repo) | (Required). Settings for the Source stage in CodePipeline. All settings are optional except for configuration.RepositoryName and BranchName. | <pre>object({<br>    name   = optional(string, "Source")<br>    action = object({<br>      name             = optional(string, "Source")<br>      category         = optional(string, "Source")<br>      owner            = optional(string, "AWS")<br>      provider         = optional(string, "CodeCommit")<br>      version          = optional(string, "1")<br>      region           = optional(string, null)<br>      output_artifacts = optional(list(string), null)<br>      role_arn         = optional(string, null)<br>      configuration    = object({<br>        RepositoryName = string<br>        BranchName     = optional(string, "master")<br>        EncryptionKey  = optional(string, null)<br>      })<br>    })<br>  })</pre> | n/a | yes |
| <a name="input_stages"></a> [stages](#input\_stages) | (Optional). List of stages for CodePipeline. configuration.ProjectName is required. | <pre>list(object({<br>    name   = string<br>    action = object({<br>      name            = optional(string, "Build")<br>      category        = optional(string, "Build")<br>      provider        = optional(string, "CodeBuild")<br>      version         = optional(string, "1")<br>      owner           = optional(string, "AWS")<br>      region          = optional(string, null)<br>      input_artifacts = optional(list(string), null)<br>      role_arn        = optional(string, null)<br>      stage_roles     = optional(list(string), [])<br>      configuration   = object({<br>        ProjectName = optional(string, null) # Override. Defaults to var.stages.name<br>      })<br>    })<br>  }))</pre> | <pre>[<br>  {<br>    "action": {<br>      "configuration": {}<br>    },<br>    "name": "Build"<br>  }<br>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_policy"></a> [policy](#output\_policy) | Service role policy. |
| <a name="output_role"></a> [role](#output\_role) | Service role information. |
<!-- END_TF_DOCS -->