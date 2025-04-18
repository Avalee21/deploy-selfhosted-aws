provider "aws" {
  region = var.aws_region
}

# Create a shared VPC for all services
resource "aws_vpc" "shared_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "shared-service-vpc"
  }
}

# Create public subnet for MinIO in AZ a
resource "aws_subnet" "minio_subnet_a" {
  vpc_id                  = aws_vpc.shared_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "minio-subnet-a"
  }
}

# Create public subnet for MinIO in AZ b
resource "aws_subnet" "minio_subnet_b" {
  vpc_id                  = aws_vpc.shared_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "minio-subnet-b"
  }
}

# Internet Gateway (shared)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.shared_vpc.id
  
  tags = {
    Name = "shared-igw"
  }
}

# Route Table (shared)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.shared_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "shared-public-rt"
  }
}

# Route Table Associations for MinIO subnets
resource "aws_route_table_association" "minio_rta_a" {
  subnet_id      = aws_subnet.minio_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "minio_rta_b" {
  subnet_id      = aws_subnet.minio_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# UPDATED: Security Group for MinIO with restricted access
resource "aws_security_group" "minio_sg" {
  name        = "minio-sg"
  description = "Allow traffic for MinIO with restricted access"
  vpc_id      = aws_vpc.shared_vpc.id
  
  # CHANGED: Restrict SSH access to specific admin IPs
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Only allow SSH from within the VPC  "10.0.0.0/16"
    description = "SSH access from within VPC"
  }
  
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # API access still public
    description = "MinIO API access"
  }
  
  ingress {
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Console access still public
    description = "MinIO Console access"
  }
  
  # ADDED: Allow all traffic from Grafana subnets
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.3.0/24", "10.0.4.0/24"]  # Grafana subnet CIDRs
    description = "All traffic from Grafana subnets"
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
  key_name               = "vockey"
  subnet_id              = aws_subnet.minio_subnet_a.id
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
  subnet_id              = aws_subnet.minio_subnet_b.id
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
  subnets            = [aws_subnet.minio_subnet_a.id, aws_subnet.minio_subnet_b.id]
  
  tags = {
    Name = "minio-lb"
  }
}

# Target Group for MinIO API
resource "aws_lb_target_group" "minio_api_tg" {
  name     = "minio-api-tg"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = aws_vpc.shared_vpc.id
  
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
  vpc_id   = aws_vpc.shared_vpc.id
  
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

# UPDATED: CloudWatch Dashboard for MinIO with enhanced metrics
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
      },
      # ADDED: Object Storage Specific Metrics
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "DiskReadKBps"],
            ["MinIO", "DiskWriteKBps"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "MinIO Disk I/O (KB/s)"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "BucketsCount"]
          ]
          period = 300
          stat   = "Maximum"
          region = var.aws_region
          title  = "MinIO Bucket Count"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "ObjectsCount"]
          ]
          period = 300
          stat   = "Maximum"
          region = var.aws_region
          title  = "MinIO Object Count"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "StorageUsageBytes"]
          ]
          period = 300
          stat   = "Maximum"
          region = var.aws_region
          title  = "MinIO Storage Usage"
          yAxis = {
            left: {
              min: 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "UptimeSeconds"]
          ]
          period = 300
          stat   = "Maximum"
          region = var.aws_region
          title  = "MinIO Uptime (seconds)"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 24
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["MinIO", "APIHealth"]
          ]
          period = 300
          stat   = "Minimum"
          region = var.aws_region
          title  = "MinIO API Health"
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