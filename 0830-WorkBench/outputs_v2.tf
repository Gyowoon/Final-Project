output "vpc_id" {
  value = aws_vpc.main.id
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "shopping_mall_service_account" {
  value = kubernetes_service_account.shopping_mall.metadata[0].name
}

output "shopping_mall_role_arn" {
  value = aws_iam_role.shopping_mall_role.arn
}

output "pod_identity_association_id" {
  value = aws_eks_pod_identity_association.shopping_mall.association_id
}

# Endpoint and public IP outputs for the newly added resources

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "rds_endpoint" {
  description = "Endpoint of the MySQL RDS instance"
  value       = aws_db_instance.db.address # endpoint를 입력하면 host:port 꼴로 나와서 문제가 됨
}

output "redis_endpoint" {
  description = "Endpoint of the Redis cluster"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}
