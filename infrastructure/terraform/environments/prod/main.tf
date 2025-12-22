module "ml_platform_prod" {
  source = "../../modules"

  project_name     = "ml-platform"
  environment      = "prod"
  aws_region       = "us-east-1"
  aws_account_id   = data.aws_caller_identity.current.account_id
  cluster_version  = "1.27"
  vpc_cidr         = "10.1.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Production-specific configurations
  tags = {
    Environment = "production"
    Project     = "ml-platform"
    ManagedBy   = "terraform"
    CostCenter  = "ml-production"
    Compliance  = "soc2"
  }
}

# Production S3 bucket for ML artifacts
resource "aws_s3_bucket" "mlflow_artifacts_prod" {
  bucket = "ml-platform-prod-mlflow-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = "production"
    Purpose     = "mlflow-artifacts"
    Compliance  = "encrypted"
  }
}

resource "aws_s3_bucket_versioning" "mlflow_artifacts_prod" {
  bucket = aws_s3_bucket.mlflow_artifacts_prod.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow_artifacts_prod" {
  bucket = aws_s3_bucket.mlflow_artifacts_prod.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mlflow_artifacts_prod" {
  bucket = aws_s3_bucket.mlflow_artifacts_prod.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# KMS key for encryption
resource "aws_kms_key" "s3_encryption" {
  description             = "KMS key for S3 encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Environment = "production"
    Purpose     = "s3-encryption"
  }
}

# WAF for API protection
resource "aws_wafv2_web_acl" "ml_platform" {
  name        = "ml-platform-prod-waf"
  description = "WAF for ML Platform production"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ml-platform-waf"
    sampled_requests_enabled   = true
  }
}

data "aws_caller_identity" "current" {}
