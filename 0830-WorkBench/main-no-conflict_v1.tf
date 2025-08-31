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

# AWS 를 Provider로 지정 
provider "aws" {  
  region = var.region
}

# Terraform 실행 시 연결된 AWS 계정 정보 조회 (aws sts get-caller-identity)
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# The following locals construct unique IAM role and policy names by
# incorporating the current AWS account ID and the cluster name.  This
# eliminates name collisions when reusing these Terraform files across
# different AWS accounts or environments without any manual imports.  If a
# duplicate role already exists in the target account, Terraform will create
# a new role with a distinct name based on these locals instead of failing.
# -----------------------------------------------------------------------------
locals {
  # Unique role names for the EKS control plane and node group.  The
  # combination of the caller's account ID and the cluster name provides
  # sufficient uniqueness across different accounts and clusters.
  cluster_role_name_unique  = "${var.cluster_role_name}-${data.aws_caller_identity.current.account_id}-${var.cluster_name}"
  node_role_name_unique     = "${var.node_role_name}-${data.aws_caller_identity.current.account_id}-${var.cluster_name}"

  # Unique names for the shopping mall IAM resources.  These names prevent
  # conflicts when the same file is applied in multiple accounts or
  # environments.
  shopping_mall_role_name_unique   = "ShoppingMallPodRole-${data.aws_caller_identity.current.account_id}-${var.cluster_name}"
  shopping_mall_policy_name_unique = "ShoppingMallPolicy-${data.aws_caller_identity.current.account_id}-${var.cluster_name}"
}

# 클러스터 생성 이후 kubernetes provider가 동작하도록 exec 사용
provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  exec { # 
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks.name, "--region", var.region]
  }
}


#### VPC 및 네트워크 생성 #####
# VPC 생성 [VPC 1개]
resource "aws_vpc" "main" { 
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # 해당 VPC 아래 추후 생성되는 리소스에 자동으로 Public DNS HostName 부여 => True로 하는게 실무적 관습  
  enable_dns_support   = true # 해당 VPC 아래 추후 생성되는 리소스가 AWS 내에서 DNS 사용 가능하게 허용 => 상동 
  tags = { 
    Name                                        = "MyVPC" # VPC 이름 
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# IGW 생성 [IGW 1개]
resource "aws_internet_gateway" "igw" { 
  vpc_id = aws_vpc.main.id
  tags   = { Name = "MyVPC-Public" }
}

# Subnet 생성 [Public, Private 각 2개]
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id # 상위 VPC 
  cidr_block              = var.public_subnet1_cidr # 해당 Subnet의 IP 주소 범위 (CIDR형식)   
  availability_zone       = "${var.region}a" # 서브넷의 AZ 
  map_public_ip_on_launch = true # 생성 시 IP 자동 할당 => Public Subnet으로 사용 시 반드시 활성화 
  tags = {
    Name                                        = "Public-SubNet-1" # 서브넷 ID 
    "kubernetes.io/role/elb"                    = "1" # EKS의 ELB와 연동가능함을 의미, 해당 태그가 붙은 퍼블릭 서브넷에서 로드밸런서가 자동 생성(Provisioning)됨
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" # 다수의 k8s 클러스터가 공통으로 사용할 수 있음을 의미함 
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

# EIP 생성 [EIP 1개]
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags   = { Name = "MyVPC-NAT-EIP" }
}

# NAT GW 생성, EIP 부착 [Internet 접근 허용된(Public) NAT GW 1개]
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id # EIP 부착 
  subnet_id     = aws_subnet.public1.id # 
  tags          = { Name = "MyVPC-NAT" }
  depends_on    = [aws_internet_gateway.igw] # IGW 생성 이후에 진행보장 (의존성)
}

# RTB 생성 [Public 1개 / Private 1개]
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id # 상위 VPC 
  route { # 라우팅 테이블에 등록할 내용 명시 
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id # 생성된 IGW 부착하여 Public으로 사용 
  }
  tags = { Name = "MyVPC-Pub-RTB" } 
}

resource "aws_route_table" "private" {  
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id # NAT GW 부착하여 Private으로 사용  
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

# -----------------------------------------------------------------------------
# IAM Roles and Policies
#
# Each role's name derives from the locals defined above to ensure that
# existing roles with the same simple name are not reused inadvertently.  If
# a role with the simple name already exists, Terraform will create a new
# role with a distinct name rather than fail due to an "EntityAlreadyExists"
# error.  Likewise, the shopping mall IAM resources are suffixed to avoid
# naming collisions.
# -----------------------------------------------------------------------------

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = local.cluster_role_name_unique
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
  name = local.node_role_name_unique
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
  name = local.shopping_mall_role_name_unique

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
  name = local.shopping_mall_policy_name_unique
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

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policies]

  # kubeconfig 자동 갱신 추가 08/27-Edited
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${self.name}"
  }
}

/*
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
*/

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

  # 변경 사항: 퍼블릭 서브넷 대신 프라이빗 서브넷에 노드를 배치합니다.  이렇게 하면
  # 노드가 인터넷에 직접 노출되지 않으므로 보안이 강화되며, NAT 게이트웨이를
  # 통해 외부와 통신할 수 있습니다.
  subnet_ids      = [aws_subnet.private1.id, aws_subnet.private2.id]

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["m7i-flex.large"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    # 변경 사항: 노드 그룹의 크기를 2 → 4로 늘려 고가용성을 보장합니다.
    desired_size = 4
    min_size     = 4
    max_size     = 4
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

# ---------------------------------------------------------------------------
# Bastion Host (Public Subnet)
#
# This section defines a bastion host that is placed in the first public
# subnet of the VPC.  The bastion is associated with a security group that
# allows inbound SSH (TCP/22) from the CIDR blocks specified in the
# `bastion_allowed_cidrs` variable, and allows all outbound traffic.  The
# instance uses the latest Amazon Linux 2023 AMI and is assigned a public IP
# address on launch.  The SSH key pair used for remote access comes from the
# `key_pair_name` variable, reusing the same key as the EKS node group.  You
# can connect to this host and use it as a jump host to reach private
# resources within the VPC.
# ---------------------------------------------------------------------------

# Look up the latest Amazon Linux 2023 AMI for the bastion host
data "aws_ami" "bastion" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-minimal-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "image-type"
    values = ["machine"]
  }
}

# Security group for the bastion host
resource "aws_security_group" "bastion" {
  name_prefix = "${var.cluster_name}-bastion-"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-bastion"
  }
}

# Bastion EC2 instance
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.bastion.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public1.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_pair_name
  
  associate_public_ip_address = true

    root_block_device {
    volume_size = 30
    volume_type = "gp3" # 또는 원하는 타입
  }

  tags = {
    Name = "${var.cluster_name}-bastion"
  }
    user_data = <<-EOF
    #!/bin/bash
    # DOCKER INSTALL
    sudo yum install -y docker
    sudo systemctl enable --now docker
    sudo usermod -aG docker ec2-user
    newgrp docker

    # KUBECTL INSTALL
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    kubectl version --client

    # HELM INSTALL
    curl -LO https://get.helm.sh/helm-v3.14.4-linux-amd64.tar.gz
    tar -zxvf helm-v3.14.4-linux-amd64.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64 helm-v3.14.4-linux-amd64.tar.gz

    # GIT INSTALL
    sudo dnf install -y git

    # MYSQL CLIENT INSTALL
    sudo dnf install -y wget
    sudo wget https://dev.mysql.com/get/mysql80-community-release-el9-4.noarch.rpm
    sudo dnf install -y mysql80-community-release-el9-4.noarch.rpm
    sudo dnf install -y mysql-community-client

    # TERRAFORM INSTALL
    sudo yum install -y yum-utils shadow-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo 
    sudo yum -y install terraform
    terraform version

    # EKSCTL INSTALL
    # 1. 최신 릴리스 다운로드
    curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

    # 2. 실행 파일을 /usr/local/bin 으로 이동
    sudo mv /tmp/eksctl /usr/local/bin

    # 3. 설치 확인
    eksctl version

  EOF
}

# ---------------------------------------------------------------------------
# MySQL RDS resources
#
# The following resources create a MySQL RDS instance in the private
# subnets.  A dedicated security group restricts inbound connections to
# within the VPC CIDR block, and a subnet group ensures the instance is
# placed into the private subnets.  The master credentials and DB name are
# supplied via variables.  Final snapshots are skipped on deletion for
# simplicity in development environments.
# ---------------------------------------------------------------------------

# Security group for RDS
resource "aws_security_group" "db" {
  name_prefix  = "${var.cluster_name}-db-"
  description  = "Security group for MySQL RDS instance"
  vpc_id       = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access from within the VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-db"
  }
}

# Subnet group for RDS
resource "aws_db_subnet_group" "db" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]
  tags = {
    Name = "${var.cluster_name}-db-subnet-group"
  }
}

# MySQL RDS instance
resource "aws_db_instance" "db" {
  identifier              = "${var.cluster_name}-db"
  engine                  = "mysql"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  username                = var.db_master_username
  password                = var.db_master_password
  db_name                 = var.db_name
  multi_az                = false
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

# ---------------------------------------------------------------------------
# ElastiCache (Redis) resources
#
# This section provisions a single-node Redis cluster in the private
# subnets.  A security group restricts inbound connections to the VPC CIDR
# block.  The subnet group ensures the cluster is created in the private
# subnets.  For more advanced configurations, you can convert this to a
# replication group with multiple nodes.
# ---------------------------------------------------------------------------

# Security group for Redis
resource "aws_security_group" "redis" {
  name_prefix  = "${var.cluster_name}-redis-"
  description  = "Security group for ElastiCache Redis"
  vpc_id       = aws_vpc.main.id

  ingress {
    description = "Allow Redis access from within the VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-redis"
  }
}

# Subnet group for Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_name}-redis-subnet-group"
  subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]
}

# Redis cluster
resource "aws_elasticache_cluster" "redis" {
  cluster_id         = "${var.cluster_name}-redis"
  engine             = "redis"
  engine_version     = var.redis_engine_version
  node_type          = var.redis_node_type
  num_cache_nodes    = var.redis_num_cache_nodes
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
  port               = 6379
}