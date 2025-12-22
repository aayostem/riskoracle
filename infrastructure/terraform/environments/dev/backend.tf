terraform {
    backend "s3" {
    bucket         = "terraform-state-$(aws sts get-caller-identity --query Account --output text)"
    key            = "ml-platform/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
