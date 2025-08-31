terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "db_password" {
  description = "Master password for the RDS database"
  type        = string
  sensitive   = true
}

# Create a VPC with public and private subnets using a community module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                 = "shop-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["${var.region}a", "${var.region}c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Create the EKS cluster and managed node group using the official EKS module
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"

  cluster_name    = "shop-eks"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # One managed node group running in private subnets
  node_groups = {
    default = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 2
      instance_types   = ["t3.medium"]
      subnets          = module.vpc.private_subnets
    }
  }
}

# Database subnet group for RDS
resource "aws_db_subnet_group" "shop" {
  name       = "shop-db-subnet-group"
  subnet_ids = module.vpc.private_subnets
  tags = {
    Name = "shop-db-subnet-group"
  }
}

# MySQL RDS instance for persistent data (e.g. products, users)
resource "aws_db_instance" "shop" {
  identifier           = "shop-db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp2"
  username             = "shopuser"
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.shop.name
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  multi_az             = false
  skip_final_snapshot  = true
}

# ElastiCache subnet group
resource "aws_elasticache_subnet_group" "shop" {
  name       = "shop-redis-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

# ElastiCache Redis cluster for session caching
resource "aws_elasticache_cluster" "shop" {
  cluster_id           = "shop-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.shop.name
  security_group_ids   = [module.vpc.default_security_group_id]
  parameter_group_name = "default.redis6.x"
}

# S3 bucket for storing product images
resource "random_id" "bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "images" {
  bucket = "shop-images-${random_id.bucket.hex}"
  acl    = "private"
  tags = {
    Name = "shop-image-bucket"
  }
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.shop.endpoint
}

output "redis_endpoint" {
  description = "Endpoint of the Redis cluster"
  value       = aws_elasticache_cluster.shop.cache_nodes[0].address
}
