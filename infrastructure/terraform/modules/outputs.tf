output "cluster_name" {
  description = "EKS cluster name"
  value       = module.kubernetes.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.kubernetes.cluster_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.networking.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.networking.public_subnets
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.redis.redis_endpoint
}

output "s3_bucket_mlflow" {
  description = "MLflow artifacts S3 bucket"
  value       = aws_s3_bucket.mlflow_artifacts.bucket
}

output "s3_bucket_data" {
  description = "Data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.bucket
}

output "mlflow_iam_role_arn" {
  description = "MLflow IAM role ARN"
  value       = aws_iam_role.mlflow_sa.arn
}
