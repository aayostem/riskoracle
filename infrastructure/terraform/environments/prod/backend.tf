terraform {
  backend "s3" {
    bucket         = "terraform-state-${data.aws_caller_identity.current.account_id}"
    key            = "ml-platform/prod/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    dynamodb_table = "terraform-state-lock-prod"
  }
}

data "aws_caller_identity" "current" {}
