# One-time setup, run from your laptop with local state:
#   S3 bucket for Terraform state, S3 bucket for app releases,
#   GitHub OIDC provider + IAM role that GitHub Actions assumes (no static keys).
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "devops-task"
}

variable "github_repo" {
  description = "GitHub repository in the form owner/repo"
  type        = string
}

variable "create_oidc_provider" {
  description = "Set false if the GitHub OIDC provider already exists in this account"
  type        = bool
  default     = true
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  buckets = {
    state    = "tfstate-${data.aws_caller_identity.current.account_id}-${var.project}"
    releases = "releases-${data.aws_caller_identity.current.account_id}-${var.project}"
  }
}

resource "aws_s3_bucket" "b" {
  for_each      = local.buckets
  bucket        = each.value
  force_destroy = true # assessment convenience; remove for production
}

resource "aws_s3_bucket_public_access_block" "b" {
  for_each                = aws_s3_bucket.b
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "b" {
  for_each = aws_s3_bucket.b
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "b" {
  for_each = aws_s3_bucket.b
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github" {
  name               = "${var.project}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Broad on purpose: the pipeline creates VPC, IAM, RDS, ALB, etc.
# In production, replace with a scoped policy.
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.github.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "TF_STATE_BUCKET" {
  value = aws_s3_bucket.b["state"].id
}

output "RELEASES_BUCKET" {
  value = aws_s3_bucket.b["releases"].id
}

output "AWS_ROLE_ARN" {
  value = aws_iam_role.github.arn
}

output "AWS_REGION" {
  value = var.region
}
