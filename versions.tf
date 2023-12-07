#
# Set providers and versions.
# These values must be hardcoded. We can't use variables here.
# https://developer.hashicorp.com/terraform/language/providers/requirements
# https://registry.terraform.io/browse/providers
#
terraform {
  required_version = ">= 1.6.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#
# Get the current AWS context
#
data "aws_caller_identity" "current" {}