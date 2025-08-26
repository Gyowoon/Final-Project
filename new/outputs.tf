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
