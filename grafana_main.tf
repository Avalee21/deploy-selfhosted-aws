provider "aws" {
  region = var.aws_region
}

# Use the shared VPC created in the MinIO configuration
data "aws_vpc" "shared_vpc" {
  filter {
    name   = "tag:Name"
    values = ["shared-service-vpc"]
  }
}

# Create public subnet for Grafana
resource "aws_subnet" "public_subnet" {
  vpc_id                  = data.aws_vpc.shared_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "grafana-public-subnet"
  }
}

# Use the shared Internet Gateway
data "aws_internet_gateway" "igw" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.shared_vpc.id]
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = data.aws_vpc.shared_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "grafana-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for Grafana with improved settings
resource "aws_security_group" "grafana_sg" {
  name        = "grafana-sg"
  description = "Allow traffic for Grafana with restricted access"
  vpc_id      = data.aws_vpc.shared_vpc.id
  
  # Restrict SSH access to within VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Only allow SSH from within the VPC
    description = "SSH access from within VPC"
  }
  
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Grafana web access still public
    description = "Grafana web access"
  }
  
  # Allow all traffic from MinIO subnets
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]  # MinIO subnet CIDRs
    description = "All traffic from MinIO subnets"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "grafana-sg"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "grafana_profile" {
  name = "grafana_profile"
  role = "LabRole"  # Using the existing LabRole in AWS Academy environment
}

# Get MinIO server information
data "aws_instances" "minio_server" {
  filter {
    name   = "tag:Name"
    values = ["minio-server"]
  }
}

# EC2 Instance for Grafana - mostly original configuration
resource "aws_instance" "grafana_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = "vockey"  # Use the existing key pair in AWS Academy
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.grafana_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.grafana_profile.name
  
  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y
              
              # Check which version of Amazon Linux we're running
              if grep -q "Amazon Linux 2" /etc/os-release; then
                # Amazon Linux 2
                amazon-linux-extras install -y epel
                yum install -y https://dl.grafana.com/oss/release/grafana-${var.grafana_version}-1.x86_64.rpm
              else
                # Amazon Linux 2023
                dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
                dnf install -y https://dl.grafana.com/oss/release/grafana-${var.grafana_version}-1.x86_64.rpm
              fi
              
              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              yum install -y unzip
              unzip awscliv2.zip
              ./aws/install
              
              # Store the MinIO server IP for later use
              MINIO_IP="${length(data.aws_instances.minio_server.public_ips) > 0 ? data.aws_instances.minio_server.public_ips[0] : "MinIO IP not found"}"
              
              # Create necessary directories for Grafana
              mkdir -p /etc/grafana/provisioning/datasources
              mkdir -p /etc/grafana/provisioning/dashboards
              mkdir -p /var/lib/grafana/dashboards
              
              # Configure CloudWatch data source
              cat > /etc/grafana/provisioning/datasources/aws-cloudwatch.yaml << 'EOL'
              apiVersion: 1
              datasources:
                - name: CloudWatch
                  type: cloudwatch
                  jsonData:
                    authType: default
                    defaultRegion: ${var.aws_region}
              EOL
              
              # Configure dashboards provider
              cat > /etc/grafana/provisioning/dashboards/dashboards.yaml << 'EOL'
              apiVersion: 1
              providers:
                - name: 'AWS'
                  orgId: 1
                  folder: 'AWS'
                  type: file
                  disableDeletion: false
                  updateIntervalSeconds: 30
                  options:
                    path: /var/lib/grafana/dashboards
              EOL
              
              # Create simplified MinIO dashboard with the most important metrics
              cat > /var/lib/grafana/dashboards/minio_dashboard.json << EOL
              {
                "annotations": {
                  "list": [
                    {
                      "builtIn": 1,
                      "datasource": "-- Grafana --",
                      "enable": true,
                      "hide": true,
                      "iconColor": "rgba(0, 211, 255, 1)",
                      "name": "Annotations & Alerts",
                      "type": "dashboard"
                    }
                  ]
                },
                "editable": true,
                "gnetId": null,
                "graphTooltip": 0,
                "id": null,
                "links": [],
                "panels": [
                  {
                    "aliasColors": {},
                    "bars": false,
                    "dashLength": 10,
                    "dashes": false,
                    "datasource": "CloudWatch",
                    "fieldConfig": {
                      "defaults": {
                        "custom": {}
                      },
                      "overrides": []
                    },
                    "fill": 1,
                    "fillGradient": 0,
                    "gridPos": {
                      "h": 8,
                      "w": 12,
                      "x": 0,
                      "y": 0
                    },
                    "hiddenSeries": false,
                    "id": 1,
                    "legend": {
                      "avg": false,
                      "current": false,
                      "max": false,
                      "min": false,
                      "show": true,
                      "total": false,
                      "values": false
                    },
                    "lines": true,
                    "linewidth": 1,
                    "nullPointMode": "null",
                    "options": {
                      "alertThreshold": true
                    },
                    "percentage": false,
                    "pointradius": 2,
                    "points": false,
                    "renderer": "flot",
                    "seriesOverrides": [],
                    "spaceLength": 10,
                    "stack": false,
                    "steppedLine": false,
                    "targets": [
                      {
                        "alias": "CPU Utilization",
                        "dimensions": {},
                        "expression": "",
                        "id": "",
                        "matchExact": true,
                        "metricName": "CPUUtilization",
                        "namespace": "MinIO",
                        "period": "",
                        "refId": "A",
                        "region": "${var.aws_region}",
                        "statistics": [
                          "Average"
                        ]
                      }
                    ],
                    "thresholds": [],
                    "timeFrom": null,
                    "timeRegions": [],
                    "timeShift": null,
                    "title": "MinIO CPU Utilization",
                    "tooltip": {
                      "shared": true,
                      "sort": 0,
                      "value_type": "individual"
                    },
                    "type": "graph",
                    "xaxis": {
                      "buckets": null,
                      "mode": "time",
                      "name": null,
                      "show": true,
                      "values": []
                    },
                    "yaxes": [
                      {
                        "format": "percent",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": 0,
                        "show": true
                      },
                      {
                        "format": "short",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": null,
                        "show": false
                      }
                    ],
                    "yaxis": {
                      "align": false,
                      "alignLevel": null
                    }
                  },
                  {
                    "aliasColors": {},
                    "bars": false,
                    "dashLength": 10,
                    "dashes": false,
                    "datasource": "CloudWatch",
                    "fieldConfig": {
                      "defaults": {
                        "custom": {}
                      },
                      "overrides": []
                    },
                    "fill": 1,
                    "fillGradient": 0,
                    "gridPos": {
                      "h": 8,
                      "w": 12,
                      "x": 12,
                      "y": 0
                    },
                    "hiddenSeries": false,
                    "id": 2,
                    "legend": {
                      "avg": false,
                      "current": false,
                      "max": false,
                      "min": false,
                      "show": true,
                      "total": false,
                      "values": false
                    },
                    "lines": true,
                    "linewidth": 1,
                    "nullPointMode": "null",
                    "options": {
                      "alertThreshold": true
                    },
                    "percentage": false,
                    "pointradius": 2,
                    "points": false,
                    "renderer": "flot",
                    "seriesOverrides": [],
                    "spaceLength": 10,
                    "stack": false,
                    "steppedLine": false,
                    "targets": [
                      {
                        "alias": "Memory Utilization",
                        "dimensions": {},
                        "expression": "",
                        "id": "",
                        "matchExact": true,
                        "metricName": "MemoryUtilization",
                        "namespace": "MinIO",
                        "period": "",
                        "refId": "A",
                        "region": "${var.aws_region}",
                        "statistics": [
                          "Average"
                        ]
                      }
                    ],
                    "thresholds": [],
                    "timeFrom": null,
                    "timeRegions": [],
                    "timeShift": null,
                    "title": "MinIO Memory Utilization",
                    "tooltip": {
                      "shared": true,
                      "sort": 0,
                      "value_type": "individual"
                    },
                    "type": "graph",
                    "xaxis": {
                      "buckets": null,
                      "mode": "time",
                      "name": null,
                      "show": true,
                      "values": []
                    },
                    "yaxes": [
                      {
                        "format": "percent",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": 0,
                        "show": true
                      },
                      {
                        "format": "short",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": null,
                        "show": false
                      }
                    ],
                    "yaxis": {
                      "align": false,
                      "alignLevel": null
                    }
                  },
                  {
                    "aliasColors": {},
                    "bars": false,
                    "dashLength": 10,
                    "dashes": false,
                    "datasource": "CloudWatch",
                    "fieldConfig": {
                      "defaults": {
                        "custom": {}
                      },
                      "overrides": []
                    },
                    "fill": 1,
                    "fillGradient": 0,
                    "gridPos": {
                      "h": 8,
                      "w": 12,
                      "x": 0,
                      "y": 8
                    },
                    "hiddenSeries": false,
                    "id": 3,
                    "legend": {
                      "avg": false,
                      "current": false,
                      "max": false,
                      "min": false,
                      "show": true,
                      "total": false,
                      "values": false
                    },
                    "lines": true,
                    "linewidth": 1,
                    "nullPointMode": "null",
                    "options": {
                      "alertThreshold": true
                    },
                    "percentage": false,
                    "pointradius": 2,
                    "points": false,
                    "renderer": "flot",
                    "seriesOverrides": [],
                    "spaceLength": 10,
                    "stack": false,
                    "steppedLine": false,
                    "targets": [
                      {
                        "alias": "Disk Read (KB/s)",
                        "dimensions": {},
                        "expression": "",
                        "id": "",
                        "matchExact": true,
                        "metricName": "DiskReadKBps",
                        "namespace": "MinIO",
                        "period": "",
                        "refId": "A",
                        "region": "${var.aws_region}",
                        "statistics": [
                          "Average"
                        ]
                      },
                      {
                        "alias": "Disk Write (KB/s)",
                        "dimensions": {},
                        "expression": "",
                        "id": "",
                        "matchExact": true,
                        "metricName": "DiskWriteKBps",
                        "namespace": "MinIO",
                        "period": "",
                        "refId": "B",
                        "region": "${var.aws_region}",
                        "statistics": [
                          "Average"
                        ]
                      }
                    ],
                    "thresholds": [],
                    "timeFrom": null,
                    "timeRegions": [],
                    "timeShift": null,
                    "title": "MinIO Disk I/O",
                    "tooltip": {
                      "shared": true,
                      "sort": 0,
                      "value_type": "individual"
                    },
                    "type": "graph",
                    "xaxis": {
                      "buckets": null,
                      "mode": "time",
                      "name": null,
                      "show": true,
                      "values": []
                    },
                    "yaxes": [
                      {
                        "format": "KBs",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": 0,
                        "show": true
                      },
                      {
                        "format": "short",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": null,
                        "show": false
                      }
                    ],
                    "yaxis": {
                      "align": false,
                      "alignLevel": null
                    }
                  },
                  {
                    "aliasColors": {},
                    "bars": false,
                    "dashLength": 10,
                    "dashes": false,
                    "datasource": "CloudWatch",
                    "fieldConfig": {
                      "defaults": {
                        "custom": {}
                      },
                      "overrides": []
                    },
                    "fill": 1,
                    "fillGradient": 0,
                    "gridPos": {
                      "h": 8,
                      "w": 12,
                      "x": 12,
                      "y": 8
                    },
                    "hiddenSeries": false,
                    "id": 4,
                    "legend": {
                      "avg": false,
                      "current": false,
                      "max": false,
                      "min": false,
                      "show": true,
                      "total": false,
                      "values": false
                    },
                    "lines": true,
                    "linewidth": 1,
                    "nullPointMode": "null",
                    "options": {
                      "alertThreshold": true
                    },
                    "percentage": false,
                    "pointradius": 2,
                    "points": false,
                    "renderer": "flot",
                    "seriesOverrides": [],
                    "spaceLength": 10,
                    "stack": false,
                    "steppedLine": false,
                    "targets": [
                      {
                        "alias": "Storage Usage",
                        "dimensions": {},
                        "expression": "",
                        "id": "",
                        "matchExact": true,
                        "metricName": "StorageUsageBytes",
                        "namespace": "MinIO",
                        "period": "",
                        "refId": "A",
                        "region": "${var.aws_region}",
                        "statistics": [
                          "Maximum"
                        ]
                      }
                    ],
                    "thresholds": [],
                    "timeFrom": null,
                    "timeRegions": [],
                    "timeShift": null,
                    "title": "MinIO Storage Usage",
                    "tooltip": {
                      "shared": true,
                      "sort": 0,
                      "value_type": "individual"
                    },
                    "type": "graph",
                    "xaxis": {
                      "buckets": null,
                      "mode": "time",
                      "name": null,
                      "show": true,
                      "values": []
                    },
                    "yaxes": [
                      {
                        "format": "bytes",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": 0,
                        "show": true
                      },
                      {
                        "format": "short",
                        "label": null,
                        "logBase": 1,
                        "max": null,
                        "min": null,
                        "show": false
                      }
                    ],
                    "yaxis": {
                      "align": false,
                      "alignLevel": null
                    }
                  }
                ],
                "refresh": "5s",
                "schemaVersion": 26,
                "style": "dark",
                "tags": [],
                "templating": {
                  "list": []
                },
                "time": {
                  "from": "now-1h",
                  "to": "now"
                },
                "timepicker": {},
                "timezone": "",
                "title": "MinIO Monitoring",
                "uid": "minio",
                "version": 1
              }
              EOL
              
              # Create welcome dashboard
              cat > /var/lib/grafana/dashboards/welcome.json << EOL
              {
                "annotations": {
                  "list": [
                    {
                      "builtIn": 1,
                      "datasource": "-- Grafana --",
                      "enable": true,
                      "hide": true,
                      "iconColor": "rgba(0, 211, 255, 1)",
                      "name": "Annotations & Alerts",
                      "type": "dashboard"
                    }
                  ]
                },
                "editable": true,
                "gnetId": null,
                "graphTooltip": 0,
                "id": 1,
                "links": [],
                "panels": [
                  {
                    "content": "# Welcome to AWS Monitoring\\n\\n## MinIO Server\\n\\nAccess your MinIO server at: http://$MINIO_IP:9001\\n\\nUsername: minio\\nPassword: minio123\\n\\n## AWS Resources\\n\\nThis Grafana instance is configured to monitor AWS resources including:\\n\\n- MinIO Server\\n- EC2 Instances\\n- CloudWatch Metrics\\n\\nCheck out the MinIO dashboard to monitor your object storage service.",
                    "datasource": null,
                    "fieldConfig": {
                      "defaults": {
                        "custom": {}
                      },
                      "overrides": []
                    },
                    "gridPos": {
                      "h": 9,
                      "w": 24,
                      "x": 0,
                      "y": 0
                    },
                    "id": 2,
                    "mode": "markdown",
                    "pluginVersion": "7.3.7",
                    "timeFrom": null,
                    "timeShift": null,
                    "title": "AWS Academy Monitoring",
                    "type": "text"
                  }
                ],
                "schemaVersion": 26,
                "style": "dark",
                "tags": [],
                "templating": {
                  "list": []
                },
                "time": {
                  "from": "now-6h",
                  "to": "now"
                },
                "timepicker": {},
                "timezone": "",
                "title": "Welcome",
                "uid": "welcome",
                "version": 0
              }
              EOL
              
              # Ensure proper ownership
              chown -R grafana:grafana /var/lib/grafana/dashboards
              
              # Start Grafana
              systemctl daemon-reload
              systemctl enable grafana-server
              systemctl start grafana-server
              EOF
  
  tags = {
    Name = "grafana-server"
  }
}

# Create S3 bucket for Grafana backups and exports
resource "aws_s3_bucket" "grafana_storage" {
  bucket_prefix = "grafana-storage-"
  
  tags = {
    Name = "grafana-storage-bucket"
  }
}

# S3 bucket policy to allow Grafana EC2 instance to access the bucket
resource "aws_s3_bucket_policy" "grafana_storage_policy" {
  bucket = aws_s3_bucket.grafana_storage.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.grafana_storage.arn,
          "${aws_s3_bucket.grafana_storage.arn}/*"
        ]
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
        }
      }
    ]
  })
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}