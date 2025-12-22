output "cluster_name" {
  description = "EKS cluster name"
  value       = module.ml_platform.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.ml_platform.cluster_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.ml_platform.vpc_id
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.ml_platform.redis_endpoint
}
