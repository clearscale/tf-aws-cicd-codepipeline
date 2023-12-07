#
# Import standardization module
#
module "context" {
  source    = "../../tf-context"
  providers = { aws = aws }

  prefix   = var.prefix
  client   = var.client
  project  = var.project
  accounts = [var.account]
  env      = var.env
  region   = var.region
  name     = var.name
  function = var.repo.action.configuration.RepositoryName
}

resource "aws_iam_role" "this" {
  name = local.iam_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "CodePipelineServiceAssumeRole",
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })

  lifecycle {
    ignore_changes = [
      tags, tags_all
    ]
  }
}

data "aws_iam_policy_document" "this" {
  dynamic "statement" {
    for_each = ((
      lower(trimspace(var.repo.action.provider)) == "codecommit"
      && var.repo.action.role_arn != null
    )
      ? ["CodeCommit"]
      : []
    )
    content {
      sid       = ""
      effect    = "Allow"
      actions   = ["sts:AssumeRole"]
      resources = [
        var.repo.action.role_arn
      ]
    }
  }

  dynamic "statement" {
    for_each = (
      length(local.updated_stages) > 0 && local.total_stage_roles > 0 ? [1] : []
    )
    content {
      sid       = "AllowInteractionBetweenCodeBuildProjects"
      effect    = "Allow"
      actions = [
        "iam:GetRole",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:DetachRolePolicy",
        "iam:ListInstanceProfilesForRole",
        "iam:ListPolicyVersions",
      ]
      resources = distinct(flatten([[
        for stage in local.updated_stages :
          try(stage.action.stage_roles, [])
      ]]))
    }
  }

  statement {
    sid       = ""
    resources = flatten([[(
        lower(trimspace(var.repo.action.provider)) == "codecommit"
        && var.repo.action.role_arn != null
        && local.account_codecommit != true
      ? [
        (var.repo.action.region != null
          ? "arn:aws:codecommit:${var.repo.action.region}:${local.account_codecommit}:${var.repo.action.configuration.RepositoryName}"
          : "arn:aws:codecommit:${var.region}:${local.account_codecommit}:${var.repo.action.configuration.RepositoryName}"
        )
      ] : [])
    ],[
      for region in local.unique_regions : [
        "arn:aws:codepipeline:${region}:${var.account.id}:${local.pipeline_name}",
      ]
    ],[
      for region in local.unique_regions : [
        for stage in local.updated_stages :
          "arn:aws:codebuild:${region}:${var.account.id}:project/${(stage.action.configuration.ProjectName)}"
          if stage.action.provider == "CodeBuild"
      ]
    ],[
      for stage in local.updated_stages :
        stage.action.role_arn
        if stage.action.provider == "CodeBuild" && stage.action.role_arn != null
    ],[
      for bucket in local.bucket_names : [
        "arn:aws:s3:::${bucket}",
        "arn:aws:s3:::${bucket}/*",
      ]
    ]])
    effect    = "Allow"
    actions   = [
      "codecommit:GitPull",
      "codecommit:Get*",
      "codecommit:List*",
      "codecommit:UploadArchive",
      "codecommit:GetUploadArchiveStatus",
      "codecommit:CancelUploadArchive",
      "cloudwatch:PutMetricData",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetMetricData",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl",
      "s3:PutObject",
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
      "codepipeline:CreatePipeline",
      "codepipeline:GetPipeline",
      "codepipeline:GetPipelineExecution",
      "codepipeline:GetPipelineState",
      "codepipeline:ListPipelines",
      "codepipeline:StartPipelineExecution",
      "codepipeline:UpdatePipeline"
    ]
  }

  dynamic "statement" {
    for_each = (
      var.repo.action.configuration.EncryptionKey != null &&
      var.repo.action.configuration.EncryptionKey != ""
        ? [1]
        : []
    )
    content {
      sid       = ""
      resources = [var.repo.action.configuration.EncryptionKey]
      effect    = "Allow"
      actions   = [
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Encrypt",
        "kms:DescribeKey",
        "kms:Decrypt"
      ]
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = local.iam_role
  description = "Default '${var.repo.action.configuration.RepositoryName}' CodePipeline policy for the '${local.project}' project."
  path        = "/"
  policy      = data.aws_iam_policy_document.this.json

  lifecycle {
    ignore_changes = [
      tags, tags_all
    ]
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = aws_iam_policy.this.arn
  role       = aws_iam_role.this.id
}

resource "aws_iam_role_policy_attachment" "cb_attachment" {
  count      = length(local.iam_service_role_policies)
  policy_arn = local.iam_service_role_policies[count.index]
  role       = aws_iam_role.this.id
}