module "ml_platform" {
  source = "../../modules"

  project_name     = "ml-platform"
  environment      = "dev"
  aws_region       = "us-east-1"
  aws_account_id   = "123456789012"  # Replace with your AWS account ID
  cluster_version  = "1.27"
  vpc_cidr         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]

  # Tags
  tags = {
    Environment = "dev"
    Project     = "ml-platform"
    ManagedBy   = "terraform"
    CostCenter  = "ml-research"
  }
}
