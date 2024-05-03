#
# Import standardization module
#
module "std" {
  source =  "github.com/clearscale/tf-standards.git?ref=v1.0.0"

  prefix   = var.prefix
  client   = var.client
  project  = var.project
  accounts = [var.account]
  env      = var.env
  region   = var.region
  name     = var.name
  function = var.repo.action.configuration.RepositoryName
}

resource "aws_codepipeline" "this" {
  name     = local.pipeline_name
  role_arn = local.iam_role

  # One artifact store per region
  dynamic "artifact_store" {
    for_each = var.artifact_stores
    content {
      type     = artifact_store.value.type
      location = replace(replace(artifact_store.value.location, "arn:aws:s3:::", ""), "_", "-")

      region   = (local.multiregion
        ? (artifact_store.value.region == null
          ? var.region
          : artifact_store.value.region
        ): null
      )

      dynamic "encryption_key" {
        for_each = (
          artifact_store.value.encryption_key != null &&
          artifact_store.value.encryption_key != ""
        ) ? [1] : []

        content {
          type = "KMS"
          id   = artifact_store.value.encryption_key
        }
      }
    }
  }

  stage {
    name = var.repo.name
    action {
      name     = var.repo.action.name
      category = var.repo.action.category
      owner    = var.repo.action.owner
      provider = var.repo.action.provider
      version  = var.repo.action.version
      role_arn = ((
        lower(trimspace(var.repo.action.provider)) == "codecommit"
        && var.repo.action.role_arn != null
      ) ? var.repo.action.role_arn
        : null
      )

      region = (var.repo.action.region == null
        ? var.region
        : var.repo.action.region
      )
      output_artifacts = (var.repo.action.output_artifacts == null
        ? [local.name]
        : var.repo.action.output_artifacts
      )

      configuration = {
        RepositoryName = var.repo.action.configuration.RepositoryName
        BranchName     = var.repo.action.configuration.BranchName
      }
    }
  }

  dynamic "stage" {
    for_each = [
      for s in local.updated_stages : s if s.action.category != "Source" || var.repo == null
    ]

    content {
      name = stage.value.name
      dynamic "action" {
        for_each = [stage.value]
        content {
          name     = action.value.action.name
          category = action.value.action.category
          provider = action.value.action.provider
          version  = action.value.action.version
          owner    = action.value.action.owner

          region = (action.value.action.region == null
            ? var.region
            : action.value.action.region
          )
          input_artifacts = (action.value.action.input_artifacts == null
            ? [local.name]
            : action.value.action.input_artifacts
          )

          configuration = {
            ProjectName = try(
              action.value.action.configuration.ProjectName,
              action.value.name
            )
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      tags, tags_all
    ]
  }
}