module "networking" {
  source = "../modules/networking"

  project_name     = var.project_name
  environment      = var.environment
  vpc_cidr         = var.vpc_cidr
  availability_zones = var.availability_zones

  tags = var.tags
}

module "kubernetes" {
  source = "../modules/kubernetes"

  project_name    = var.project_name
  environment     = var.environment
  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnets
  cluster_version = var.cluster_version

  tags = var.tags
}

module "redis" {
  source = "../modules/databases"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = module.networking.vpc_cidr_block
  subnet_ids   = module.networking.private_subnets

  tags = var.tags
}

# S3 Buckets
resource "aws_s3_bucket" "mlflow_artifacts" {
  bucket = "${var.project_name}-${var.environment}-mlflow-artifacts"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-${var.environment}-data-lake"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Roles for Service Accounts
resource "aws_iam_role" "mlflow_sa" {
  name = "${var.project_name}-${var.environment}-mlflow-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.kubernetes.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.kubernetes.oidc_provider_arn}:sub" = "system:serviceaccount:ml-platform:mlflow"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "mlflow_s3" {
  name = "${var.project_name}-${var.environment}-mlflow-s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.mlflow_artifacts.arn,
          "${aws_s3_bucket.mlflow_artifacts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mlflow_s3" {
  role       = aws_iam_role.mlflow_sa.name
  policy_arn = aws_iam_policy.mlflow_s3.arn
}
