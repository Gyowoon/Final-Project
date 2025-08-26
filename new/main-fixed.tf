terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# 클러스터 생성 이후 kubernetes provider가 동작하도록 exec 사용
provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks.name, "--region", var.region]
  }
}


# VPC 및 네트워크
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name                                        = "MyVPC" # This is your VPC Name 
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "MyVPC-Public" }
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet1_cidr
  availability_zone       = "${var.region}a" # This is Your Subnet's AZ 
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "Public-SubNet-1" # This is Your Subnet Name 
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet2_cidr
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "Public-SubNet-2" 
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet1_cidr
  availability_zone = "${var.region}a"
  tags = {
    Name                                        = "Private-SubNet-1"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet2_cidr
  availability_zone = "${var.region}c"
  tags = {
    Name                                        = "Private-SubNet-2"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags   = { Name = "MyVPC-NAT-EIP" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public1.id
  tags          = { Name = "MyVPC-NAT" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "MyVPC-Pub-RTB" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "MyVPC-Pri-RTB" }
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = var.cluster_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policies" {
  count      = length(var.cluster_policies)
  role       = aws_iam_role.eks_cluster.name
  policy_arn = var.cluster_policies[count.index]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_node" {
  name = var.node_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  count      = length(var.node_policies)
  role       = aws_iam_role.eks_node.name
  policy_arn = var.node_policies[count.index]
}

# 쇼핑몰 애플리케이션용 IAM 역할 (Pod Identity)
resource "aws_iam_role" "shopping_mall_role" {
  name = "ShoppingMallPodRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# 쇼핑몰 애플리케이션에 필요한 AWS 서비스 접근 권한
resource "aws_iam_role_policy" "shopping_mall_policy" {
  name = "ShoppingMallPolicy"
  role = aws_iam_role.shopping_mall_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # RDS 접근
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:Connect",
          # ElastiCache 접근
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeReplicationGroups",
          "elasticache:Connect",
          # S3 접근 (상품 이미지 등)
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          # Secrets Manager 접근 (DB 패스워드 등)
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          # CloudWatch 로그
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          # Parameter Store 접근
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      }
    ]
  })
}

# EKS Cluster with Access Entries
resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.k8s_version

  vpc_config {
    subnet_ids = [
      aws_subnet.public1.id,
      aws_subnet.public2.id,
      aws_subnet.private1.id,
      aws_subnet.private2.id,
    ]

    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
  }

  # Access Entries 모드 설정 - bootstrap 권한은 true로 유지
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policies]
}

# EKS Add-ons VPC_CNI
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_cluster.eks]
}

# EKS Add-ons KUBE_PROXY
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_cluster.eks]
}

# EKS Pod Identity Agent 애드온
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_cluster.eks]
}

# EKS Add-Ons COREDNS 
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "coredns"
  depends_on = [
    aws_eks_node_group.nodes,
    aws_eks_addon.vpc_cni
  ]
}

# Access Entry 제거 - bootstrap 권한으로 자동 생성되므로 불필요
# user1에 대한 Access Entry는 클러스터 생성시 자동으로 생성됨

# EKS Node Group
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.public1.id, aws_subnet.public2.id]

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["m7i-flex.large"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  disk_size = 20

  remote_access {
    ec2_ssh_key = var.key_pair_name
  }


  # Add-on 완료 후 Node Group 생성
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.node_policies
  ]
}

# Kubernetes Service Account 생성
resource "kubernetes_service_account" "shopping_mall" {
  metadata {
    name      = "shopping-mall-sa"
    namespace = "default"
  }

  depends_on = [
    aws_eks_node_group.nodes,
    aws_eks_addon.coredns
  ]
}

# Pod Identity Association 생성
resource "aws_eks_pod_identity_association" "shopping_mall" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "default"
  service_account = "shopping-mall-sa"
  role_arn        = aws_iam_role.shopping_mall_role.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role.shopping_mall_role,
    kubernetes_service_account.shopping_mall
  ]
}