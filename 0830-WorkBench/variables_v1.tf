variable "region" { default = "ap-northeast-2" }
variable "vpc_cidr" { default = "10.10.0.0/16" }
variable "public_subnet1_cidr" { default = "10.10.1.0/24" }
variable "public_subnet2_cidr" { default = "10.10.2.0/24" }
variable "private_subnet1_cidr" { default = "10.10.11.0/24" }
variable "private_subnet2_cidr" { default = "10.10.12.0/24" }

variable "cluster_name" { default = "my-default-cluster" }
variable "cluster_role_name" { default = "YourEKSClusterRole" }
variable "cluster_policies" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
  ]
}

variable "node_group_name" { default = "YourEKSNodeGroups" }
variable "node_role_name" { default = "YourEKSNodeRole" }
variable "node_policies" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",          # MinimalPolicy 대신 사용
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # PullOnly 대신 사용
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"                # 누락된 필수 정책 추가
  ]
}

variable "k8s_version" { default = "1.33" }
variable "key_pair_name" { description = "Existing SSH key pair name" }
variable "public_access_cidrs" {
  description = "EKS 공개 API 엔드포인트 접근 허용 CIDR 목록"
  type        = list(string)
  # 보안상 권장: 본인 공인IP/32만 허용. (임시로 0.0.0.0/0 사용 가능)
  default = ["0.0.0.0/0"]
}

# -------------------------------------------------------------------------------------------------
# Bastion configuration variables
# -------------------------------------------------------------------------------------------------

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed to access the bastion via SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -------------------------------------------------------------------------------------------------
# RDS configuration variables
# -------------------------------------------------------------------------------------------------

variable "db_name" {
  description = "Name of the MySQL database to create on RDS"
  type        = string
  default     = "shopdb"
}

variable "db_master_username" {
  description = "Master username for the RDS database"
  type        = string
  default     = "admin"
}

variable "db_master_password" {
  description = "Master user password for the RDS database"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for the RDS instance"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "Version of the MySQL engine to use for RDS"
  type        = string
  default     = "8.0"
}

# -------------------------------------------------------------------------------------------------
# ElastiCache (Redis) configuration variables
# -------------------------------------------------------------------------------------------------

variable "redis_node_type" {
  description = "Node type for the Redis cluster"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Version of the Redis engine to use"
  type        = string
  default     = "6.x"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes in the Redis cluster"
  type        = number
  default     = 1
}
