output "vpc_id" {
  value = aws_vpc.main.id
}
output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}
output "cluster_name" {
  value = aws_eks_cluster.eks.name
}
