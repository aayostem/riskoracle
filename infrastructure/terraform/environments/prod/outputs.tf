output "cluster_name" {
  description = "EKS cluster name"
  value       = module.ml_platform_prod.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.ml_platform_prod.cluster_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.ml_platform_prod.vpc_id
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.ml_platform_prod.redis_endpoint
}

output "s3_bucket_mlflow" {
  description = "MLflow artifacts S3 bucket"
  value       = aws_s3_bucket.mlflow_artifacts_prod.bucket
}

output "waf_arn" {
  description = "WAF ARN"
  value       = aws_wafv2_web_acl.ml_platform.arn
}

output "kms_key_arn" {
  description = "KMS key ARN for encryption"
  value       = aws_kms_key.s3_encryption.arn
}
