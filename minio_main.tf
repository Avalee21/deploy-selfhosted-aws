provider "aws" {
  region = var.aws_region
}

# Create a VPC for MinIO
resource "aws_vpc" "minio_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "minio-vpc"
  }
}

# Create public subnet in AZ a
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.minio_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "minio-subnet-a"
  }
}

# Create public subnet in AZ b
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.minio_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "minio-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.minio_vpc.id
  
  tags = {
    Name = "minio-igw"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.minio_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "minio-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rta_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for MinIO
resource "aws_security_group" "minio_sg" {
  name        = "minio-sg"
  description = "Allow traffic for MinIO"
  vpc_id      = aws_vpc.minio_vpc.id
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }
  
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MinIO API access"
  }
  
  ingress {
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MinIO Console access"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "minio-sg"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "minio_profile" {
  name = "minio_profile"
  role = "LabRole"  # Using the existing LabRole in AWS Academy
}

# EC2 Instance for MinIO in AZ a
resource "aws_instance" "minio_server_a" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = "vockey"  # Use the existing key pair in AWS Academy
  subnet_id              = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.minio_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.minio_profile.name
  
  # EBS volume for MinIO data
  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }
  
  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y
              
              # Install Docker
              yum install docker -y
              systemctl start docker
              systemctl enable docker
              
              # Create MinIO data directory
              mkdir -p /minio/data
              
              # Run MinIO container
              docker run -d \
                --name minio \
                --restart always \
                -p 9000:9000 \
                -p 9001:9001 \
                -e "MINIO_ROOT_USER=minio" \
                -e "MINIO_ROOT_PASSWORD=minio123" \
                -v /minio/data:/data \
                minio/minio server /data --console-address ":9001"
              
              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              yum install -y unzip
              unzip awscliv2.zip
              ./aws/install
              
              # Set up CloudWatch metrics
              echo '*/5 * * * * root /usr/local/bin/aws cloudwatch put-metric-data --metric-name DiskUtilization --namespace MinIO --value $(df -h | grep /dev/xvda1 | awk "{print \$5}" | sed "s/%//") --region us-east-1' > /etc/cron.d/cloudwatch-metrics
              echo '*/5 * * * * root /usr/local/bin/aws cloudwatch put-metric-data --metric-name MemoryUtilization --namespace MinIO --value $(free | grep Mem | awk "{print \$3/\$2 * 100.0}") --region us-east-1' >> /etc/cron.d/cloudwatch-metrics
              chmod 644 /etc/cron.d/cloudwatch-metrics
              EOF
  
  tags = {
    Name = "minio-server-a"
  }
}

# EC2 Instance for MinIO in AZ b
resource "aws_instance" "minio_server_b" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = "vockey"  # Use the existing key pair in AWS Academy
  subnet_id              = aws_subnet.public_subnet_b.id
  vpc_security_group_ids = [aws_security_group.minio_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.minio_profile.name
  
  # EBS volume for MinIO data
  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }
  
  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y
              
              # Install Docker
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              
              # Create MinIO data directory
              mkdir -p /minio/data
              
              # Run MinIO container
              docker run -d \
                --name minio \
                --restart always \
                -p 9000:9000 \
                -p 9001:9001 \
                -e "MINIO_ROOT_USER=minio" \
                -e "MINIO_ROOT_PASSWORD=minio123" \
                -v /minio/data:/data \
                minio/minio server /data --console-address ":9001"
              
              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              yum install -y unzip
              unzip awscliv2.zip
              ./aws/install
              
              # Set up CloudWatch metrics
              echo '*/5 * * * * root /usr/local/bin/aws cloudwatch put-metric-data --metric-name DiskUtilization --namespace MinIO --value $(df -h | grep /dev/xvda1 | awk "{print \$5}" | sed "s/%//") --region us-east-1' > /etc/cron.d/cloudwatch-metrics
              echo '*/5 * * * * root /usr/local/bin/aws cloudwatch put-metric-data --metric-name MemoryUtilization --namespace MinIO --value $(free | grep Mem | awk "{print \$3/\$2 * 100.0}") --region us-east-1' >> /etc/cron.d/cloudwatch-metrics
              chmod 644 /etc/cron.d/cloudwatch-metrics
              EOF
  
  tags = {
    Name = "minio-server-b"
  }
}

# Load Balancer for MinIO
resource "aws_lb" "minio_lb" {
  name               = "minio-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.minio_sg.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  
  tags = {
    Name = "minio-lb"
  }
}

# Target Group for MinIO API
resource "aws_lb_target_group" "minio_api_tg" {
  name     = "minio-api-tg"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = aws_vpc.minio_vpc.id
  
  health_check {
    path                = "/minio/health/live"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

# Target Group for MinIO Console
resource "aws_lb_target_group" "minio_console_tg" {
  name     = "minio-console-tg"
  port     = 9001
  protocol = "HTTP"
  vpc_id   = aws_vpc.minio_vpc.id
  
  health_check {
    path                = "/login"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

# Register instances with target groups
resource "aws_lb_target_group_attachment" "minio_api_tg_attachment_a" {
  target_group_arn = aws_lb_target_group.minio_api_tg.arn
  target_id        = aws_instance.minio_server_a.id
  port             = 9000
}

resource "aws_lb_target_group_attachment" "minio_api_tg_attachment_b" {
  target_group_arn = aws_lb_target_group.minio_api_tg.arn
  target_id        = aws_instance.minio_server_b.id
  port             = 9000
}

resource "aws_lb_target_group_attachment" "minio_console_tg_attachment_a" {
  target_group_arn = aws_lb_target_group.minio_console_tg.arn
  target_id        = aws_instance.minio_server_a.id
  port             = 9001
}

resource "aws_lb_target_group_attachment" "minio_console_tg_attachment_b" {
  target_group_arn = aws_lb_target_group.minio_console_tg.arn
  target_id        = aws_instance.minio_server_b.id
  port             = 9001
}

# Listener rules for MinIO API
resource "aws_lb_listener" "minio_api_listener" {
  load_balancer_arn = aws_lb.minio_lb.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_api_tg.arn
  }
}

# Listener rules for MinIO Console
resource "aws_lb_listener" "minio_console_listener" {
  load_balancer_arn = aws_lb.minio_lb.arn
  port              = 9001
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_console_tg.arn
  }
}

# CloudWatch Dashboard for MinIO
resource "aws_cloudwatch_dashboard" "minio_dashboard" {
  dashboard_name = "MinIO-Metrics-Dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.minio_server_a.id],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.minio_server_b.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "MinIO Servers CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.minio_server_a.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.minio_server_a.id],
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.minio_server_b.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.minio_server_b.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "MinIO Network Traffic"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "DiskUtilization"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "MinIO Disk Utilization"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "MemoryUtilization"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "MinIO Memory Utilization"
        }
      }
    ]
  })
}

output "minio_lb_dns_name" {
  description = "DNS name of the MinIO load balancer"
  value       = aws_lb.minio_lb.dns_name
}

output "minio_api_url" {
  description = "URL to access MinIO API"
  value       = "http://${aws_lb.minio_lb.dns_name}"
}

output "minio_console_url" {
  description = "URL to access MinIO Console"
  value       = "http://${aws_lb.minio_lb.dns_name}:9001"
}

output "minio_server_a_ip" {
  description = "Public IP of MinIO server in AZ a"
  value       = aws_instance.minio_server_a.public_ip
}

output "minio_server_b_ip" {
  description = "Public IP of MinIO server in AZ b"
  value       = aws_instance.minio_server_b.public_ip
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.minio_dashboard.dashboard_name}"
}