locals {
  client       = lower(replace(var.client, " ", "-"))
  project      = lower(replace(var.project, " ", "-"))
  name         = lower(replace(var.name, " ", "-"))

  prefix = (try(
    trimspace(var.prefix),
    "${local.client}-${local.project}")
  )

  pipeline_name = ((
    local.name == null || local.name == "" || local.name == "default"
  ) ? local.prefix
    : "${local.prefix}-${local.name}"
  )

  iam_service_role_policies = (var.iam_service_role_policies == null
    ? []
    : var.iam_service_role_policies
  )

  stage_regions = [
    for s in var.stages : s.action.region if s.action.region != null
  ]

  unique_regions = (length(local.stage_regions) > 0
    ? distinct(local.stage_regions)
    : [var.region]
  )

  # multiregion = (length(local.unique_regions) > 1
  #   ? true
  #   : false
  # )

  bucket_names = [
    for s in var.artifact_stores : replace(replace(s.location, "arn:aws:s3:::", ""), "_", "-")
      if s != null && upper(s.type) == "S3"
  ]

  rex_arn = "arn:aws:([^:]+)?:([^:]+)?:([0-9]+)?:"
  account_codecommit = try(
    regex(local.rex_arn, var.repo.action.role_arn)[2], true
  )

  # Get IAM role names from standardization module output
  context    = jsondecode(jsonencode(module.context.accounts))
  iam_role   = local.context.aws[0].prefix.dot.full.function

  # Set var.stages[x].action.configuration.ProjectName with var.stages[x].name if null or empty
  updated_stages = [for stage in var.stages : {
    name = stage.name
    action = {
      name            = stage.action.name
      category        = stage.action.category
      provider        = stage.action.provider
      version         = stage.action.version
      owner           = stage.action.owner
      region          = stage.action.region
      input_artifacts = stage.action.input_artifacts
      role_arn        = stage.action.role_arn
      stage_roles     = stage.action.stage_roles
      configuration   = {
        ProjectName = coalesce(stage.action.configuration.ProjectName, stage.name)
      }
    }
  }]

   total_stage_roles = sum([for stage in local.updated_stages : length(stage.action.stage_roles)])
}

variable "prefix" {
  type        = string
  description = "(Optional). Prefix override for all generated naming conventions."
  default     = "cs"
}

variable "client" {
  type        = string
  description = "(Optional). Name of the client."
  default     = "ClearScale"
}

variable "project" {
  type        = string
  description = "(Optional). Name of the client project."
  default     = "pmod"
}

variable "account" {
  description = "(Optional). Cloud provider account object."
  type = object({
    key      = optional(string, "current")
    provider = optional(string, "aws")
    id       = optional(string, "*") 
    name     = string
    region   = optional(string, null)
  })
  default = {
    id   = "*"
    name = "shared"
  }
}

variable "env" {
  type        = string
  description = "(Optional). Name of the current environment."
  default     = "dev"
}

variable "region" {
  type        = string
  description = "(Optional). AWS region."
  default     = "us-west-1"
}

variable "name" {
  type        = string
  description = "(Optional). The name of the pipeline."
  default     = "codepipeline"
}

#
# Additional IAM policy ARNs for the primary IAM service role.
# Example:
#   iam_assume_role_policies = ["arn:aws:iam::aws:policy/PowerUserAccess"]
#
variable "iam_service_role_policies" {
  description = "(Optional). List of IAM policy ARNs to attach to the primary service role."
  type        = list(string)
  default     = []
}

#
# Define where artifacts and cache will be stored. Currently only S3 is supported.
# Also, multi-region stores have not been tested.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codepipeline#artifact_store
#
variable "artifact_stores" {
  description = "(Required). Artifact data stores. Currently only S3 is supported and mult-region stores have not been tested."
  type = list(object({
    type             = optional(string, "S3")
    location         = string
    region           = optional(string, null)
    encryption_key   = optional(string, null)
  }))
}

#
# Define Source stages separately here. Defining anything here other than null
# will cause var.stages to omit any Source definitions defined there.
# If not null, configuration.RepositoryName && BranchName must be defined.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codepipeline#stage
#
variable "repo" {
  description = "(Required). Settings for the Source stage in CodePipeline. All settings are optional except for configuration.RepositoryName and BranchName."
  type = object({
    name   = optional(string, "Source")
    action = object({
      name             = optional(string, "Source")
      category         = optional(string, "Source")
      owner            = optional(string, "AWS")
      provider         = optional(string, "CodeCommit")
      version          = optional(string, "1")
      region           = optional(string, null)
      output_artifacts = optional(list(string), null)
      role_arn         = optional(string, null)
      configuration    = object({
        RepositoryName = string
        BranchName     = optional(string, "master")
        EncryptionKey  = optional(string, null)
      })
    })
  })
}

#
# A list of stages and their parameters.
# Will skip "Source" stages if var.repo != null.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codepipeline#stage
#
variable "stages" {
  description = "(Optional). List of stages for CodePipeline. configuration.ProjectName is required."
  type = list(object({
    name   = string
    action = object({
      name            = optional(string, "Build")
      category        = optional(string, "Build")
      provider        = optional(string, "CodeBuild")
      version         = optional(string, "1")
      owner           = optional(string, "AWS")
      region          = optional(string, null)
      input_artifacts = optional(list(string), null)
      role_arn        = optional(string, null)
      stage_roles     = optional(list(string), [])
      configuration   = object({
        ProjectName = optional(string, null) # Override. Defaults to var.stages.name
      })
    })
  }))
  default = [{
    name   = "Build"
    action = {
      configuration = {}
    }
  }]
}