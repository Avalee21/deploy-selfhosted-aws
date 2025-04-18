variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"  # Limited to us-east-1 in AWS Academy
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"  # Same as the MinIO VPC CIDR
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.5.0/24"  # Different from MinIO subnets
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0f34c5ae932e6f0e4"  # Amazon Linux 2 AMI in us-east-1
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.micro"  # Supported in AWS Academy
}

variable "grafana_version" {
  description = "Grafana version to install"
  type        = string
  default     = "10.0.3"  # Update as needed
}