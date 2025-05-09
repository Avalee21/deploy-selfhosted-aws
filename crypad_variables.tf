variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"  # Limited to us-east-1 in AWS Academy
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cryptpad_subnet_cidr" {
  description = "CIDR block for the Cryptpad subnet"
  type        = string
  default     = "10.0.6.0/24"  # Different from MinIO and Grafana subnets
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-084568db4383264d4"  # Latest Ubuntu AMI in us-east-1
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.small"  # 2 vCPUs & 2GB RAM as specified
}