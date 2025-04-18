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

# Create public subnet for Cryptpad
resource "aws_subnet" "cryptpad_subnet" {
  vpc_id                  = data.aws_vpc.shared_vpc.id
  cidr_block              = var.cryptpad_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "cryptpad-public-subnet"
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
resource "aws_route_table" "cryptpad_rt" {
  vpc_id = data.aws_vpc.shared_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "cryptpad-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "cryptpad_rta" {
  subnet_id      = aws_subnet.cryptpad_subnet.id
  route_table_id = aws_route_table.cryptpad_rt.id
}

# Security Group for Cryptpad
resource "aws_security_group" "cryptpad_sg" {
  name        = "cryptpad-sg"
  description = "Allow traffic for Cryptpad"
  vpc_id      = data.aws_vpc.shared_vpc.id
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }
  
  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }
  
  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }
  
  # Node.js server port
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Cryptpad Node.js server"
  }
  
  # Sandbox port
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Cryptpad sandbox port"
  }
  
  # WebSocket port
  ingress {
    from_port   = 3003
    to_port     = 3003
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Cryptpad websocket"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "cryptpad-sg"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "cryptpad_profile" {
  name = "cryptpad_profile"
  role = "LabRole"  # Using the existing LabRole in AWS Academy environment
}

# Elastic IP for Cryptpad
resource "aws_eip" "cryptpad_eip" {
  domain = "vpc"
  
  tags = {
    Name = "cryptpad-eip"
  }
}

# EC2 Instance for Cryptpad
resource "aws_instance" "cryptpad_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = "vockey"  # Use the existing key pair in AWS Academy
  subnet_id              = aws_subnet.cryptpad_subnet.id
  vpc_security_group_ids = [aws_security_group.cryptpad_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.cryptpad_profile.name
  
  # EBS volume that doesn't get deleted on termination
  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = false
  }
  
  user_data = <<-EOF
#!/bin/bash
# Update and install dependencies
apt update
apt install -y git

# Install Node.js with NPM
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

# Install AWS CLI
snap install aws-cli --classic

# Clone CryptPad repository
cd /home/ubuntu
git clone -b 2025.3.0 --depth 1 https://github.com/cryptpad/cryptpad.git cryptpad
cd cryptpad

# Install dependencies
npm ci
npm run install:components

# Create required directories with proper permissions
mkdir -p /home/ubuntu/cryptpad/data
mkdir -p /home/ubuntu/cryptpad/datastore
mkdir -p /home/ubuntu/cryptpad/block
mkdir -p /home/ubuntu/cryptpad/blob
mkdir -p /home/ubuntu/cryptpad/data/archive
mkdir -p /home/ubuntu/cryptpad/data/pins
mkdir -p /home/ubuntu/cryptpad/data/tasks
mkdir -p /home/ubuntu/cryptpad/data/logs
mkdir -p /home/ubuntu/cryptpad/data/blobstage
mkdir -p /home/ubuntu/cryptpad/data/decrees

# Ensure proper ownership
chown -R ubuntu:ubuntu /home/ubuntu/cryptpad

# Setup configuration
cp config/config.example.js config/config.js

# Create a script to update the config with the Elastic IP
cat > /home/ubuntu/update_cryptpad_ip.sh << 'SCRIPT'
#!/bin/bash
# Get the Elastic IP from AWS metadata
ELASTIC_IP=$(aws ec2 describe-addresses --filters "Name=instance-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)" --query 'Addresses[0].PublicIp' --output text)

if [ -z "$ELASTIC_IP" ] || [ "$ELASTIC_IP" == "None" ]; then
  # Fallback to the public IP if Elastic IP isn't found
  ELASTIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
fi

if [ -z "$ELASTIC_IP" ]; then
  # If we still don't have an IP, use the private IP
  ELASTIC_IP=$(hostname -I | awk '{print $1}')
fi

echo "Updating Cryptpad configuration with IP: $ELASTIC_IP"
sed -i "s/CRYPTPAD_IP_PLACEHOLDER/$ELASTIC_IP/g" /home/ubuntu/cryptpad/config/config.js
SCRIPT

chmod +x /home/ubuntu/update_cryptpad_ip.sh

# Update config.js with our settings
cat > config/config.js << 'CONFIGEOF'
module.exports = {
  httpUnsafeOrigin: 'http://CRYPTPAD_IP_PLACEHOLDER:3000',
  httpSafeOrigin: '',
  httpAddress: '0.0.0.0',
  httpPort: 3000,
  httpSafePort: 3001,
  websocketPort: 3003,
  maxWorkers: 4,
  otpSessionExpiration: 7*24,
  inactiveTime: 90,
  archiveRetentionTime: 15,
  accountRetentionTime: 365,
  disableIntegratedEviction: true,
  maxUploadSize: 20 * 1024 * 1024,
  premiumUploadSize: 100 * 1024 * 1024,
  filePath: './datastore/',
  archivePath: './data/archive',
  pinPath: './data/pins',
  taskPath: './data/tasks',
  blockPath: './block',
  blobPath: './blob',
  blobStagingPath: './data/blobstage',
  decreePath: './data/decrees',
  logPath: './data/logs',
  logToStdout: true,
  logLevel: 'info',
  logFeedback: false,
  verbose: false,
  installMethod: 'terraform-aws-academy',
};
CONFIGEOF

# Create backup script
cat > /home/ubuntu/backup_to_s3.sh << 'BACKUPEOF'
#!/bin/bash
TIMESTAMP=$(date +%F-%H%M)
S3_BUCKET="${aws_s3_bucket.cryptpad_backup.id}"
S3_BASE_PATH="s3://$S3_BUCKET/backup/$TIMESTAMP"
CRYPTPAD_DIR="/home/ubuntu/cryptpad"

# Backup data directory
if [ -e "$CRYPTPAD_DIR/data" ]; then
    echo "Backing up $CRYPTPAD_DIR/data"
    aws s3 cp "$CRYPTPAD_DIR/data" "$S3_BASE_PATH/data" --recursive
else
    echo "Warning: $CRYPTPAD_DIR/data does not exist"
fi

# Backup datastore directory
if [ -e "$CRYPTPAD_DIR/datastore" ]; then
    echo "Backing up $CRYPTPAD_DIR/datastore"
    aws s3 cp "$CRYPTPAD_DIR/datastore" "$S3_BASE_PATH/datastore" --recursive
else
    echo "Warning: $CRYPTPAD_DIR/datastore does not exist"
fi

# Backup block directory
if [ -e "$CRYPTPAD_DIR/block" ]; then
    echo "Backing up $CRYPTPAD_DIR/block"
    aws s3 cp "$CRYPTPAD_DIR/block" "$S3_BASE_PATH/block" --recursive
else
    echo "Warning: $CRYPTPAD_DIR/block does not exist"
fi

# Backup blob directory
if [ -e "$CRYPTPAD_DIR/blob" ]; then
    echo "Backing up $CRYPTPAD_DIR/blob"
    aws s3 cp "$CRYPTPAD_DIR/blob" "$S3_BASE_PATH/blob" --recursive
else
    echo "Warning: $CRYPTPAD_DIR/blob does not exist"
fi

# Backup config file
if [ -e "$CRYPTPAD_DIR/config/config.js" ]; then
    echo "Backing up $CRYPTPAD_DIR/config/config.js"
    mkdir -p /tmp/cryptpad-backup/config
    cp "$CRYPTPAD_DIR/config/config.js" /tmp/cryptpad-backup/config/
    aws s3 cp /tmp/cryptpad-backup "$S3_BASE_PATH" --recursive
    rm -rf /tmp/cryptpad-backup
else
    echo "Warning: $CRYPTPAD_DIR/config/config.js does not exist"
fi

echo "Backup completed at $(date)"
BACKUPEOF

chmod +x /home/ubuntu/backup_to_s3.sh

# Set up cron jobs
(crontab -l 2>/dev/null || echo "") > /tmp/cryptpad-crontab
echo "0 0 * * * /usr/bin/node /home/ubuntu/cryptpad/scripts/evict-inactive.js > /dev/null" >> /tmp/cryptpad-crontab
echo "0 0 * * 0 /usr/bin/node /home/ubuntu/cryptpad/scripts/evict-archived.js > /dev/null" >> /tmp/cryptpad-crontab
echo "0 3 * * * /home/ubuntu/backup_to_s3.sh >> /var/log/cryptpad_backup.log 2>&1" >> /tmp/cryptpad-crontab
crontab /tmp/cryptpad-crontab

# Create system service file
cat > /etc/systemd/system/cryptpad.service << 'SERVICEEOF'
[Unit]
Description=CryptPad API server

[Service]
ExecStart=/usr/bin/node /home/ubuntu/cryptpad/server.js
WorkingDirectory=/home/ubuntu/cryptpad
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal+console
User=ubuntu
Group=ubuntu
Environment='PWD="/home/ubuntu/cryptpad"'
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Enable the service
systemctl daemon-reload
systemctl enable cryptpad

# Associate Elastic IP with instance (via AWS CLI, as a fallback)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
ALLOCATION_ID=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=cryptpad-eip" --query 'Addresses[0].AllocationId' --output text)

if [ -n "$ALLOCATION_ID" ] && [ -n "$INSTANCE_ID" ]; then
  aws ec2 associate-address --allocation-id $ALLOCATION_ID --instance-id $INSTANCE_ID
fi

# Wait for Elastic IP association to complete
sleep 30

# Run the IP update script
/home/ubuntu/update_cryptpad_ip.sh

# Start Cryptpad after the IP is updated
systemctl start cryptpad

# Build static pages
cd /home/ubuntu/cryptpad
npm run build
EOF

  tags = {
    Name = "cryptpad-instance"
  }
}

# Associate Elastic IP with instance
resource "aws_eip_association" "cryptpad_eip_assoc" {
  instance_id   = aws_instance.cryptpad_server.id
  allocation_id = aws_eip.cryptpad_eip.id
}

# S3 bucket for Cryptpad backups
resource "aws_s3_bucket" "cryptpad_backup" {
  bucket_prefix = "cryptpad-backup-"
  
  tags = {
    Name = "cryptpad-backup-bucket"
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "cryptpad_backup_block" {
  bucket = aws_s3_bucket.cryptpad_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable bucket versioning
resource "aws_s3_bucket_versioning" "cryptpad_backup_versioning" {
  bucket = aws_s3_bucket.cryptpad_backup.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket policy to allow the Cryptpad instance to access the bucket
resource "aws_s3_bucket_policy" "cryptpad_backup_policy" {
  bucket = aws_s3_bucket.cryptpad_backup.id
  
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
          aws_s3_bucket.cryptpad_backup.arn,
          "${aws_s3_bucket.cryptpad_backup.arn}/*"
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

# CloudWatch dashboard for monitoring Cryptpad
resource "aws_cloudwatch_dashboard" "cryptpad_dashboard" {
  dashboard_name = "Cryptpad-Metrics-Dashboard"
  
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
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.cryptpad_server.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Cryptpad CPU Utilization"
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
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.cryptpad_server.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.cryptpad_server.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Cryptpad Network Traffic"
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
            ["AWS/EC2", "DiskReadBytes", "InstanceId", aws_instance.cryptpad_server.id],
            ["AWS/EC2", "DiskWriteBytes", "InstanceId", aws_instance.cryptpad_server.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Cryptpad Disk I/O"
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
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.cryptpad_server.id]
          ]
          period = 60
          stat   = "Maximum"
          region = var.aws_region
          title  = "Cryptpad Status Checks"
        }
      }
    ]
  })
}

# Output variables
output "cryptpad_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.cryptpad_server.id
}

output "cryptpad_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.cryptpad_eip.public_ip
}

output "cryptpad_elastic_ip" {
  description = "Elastic IP address for Cryptpad"
  value       = aws_eip.cryptpad_eip.public_ip
}

output "cryptpad_url" {
  description = "URL to access Cryptpad"
  value       = "http://${aws_eip.cryptpad_eip.public_ip}:3000"
}

output "cryptpad_login_instructions" {
  description = "Instructions to access Cryptpad"
  value       = "Access Cryptpad at http://${aws_eip.cryptpad_eip.public_ip}:3000. No login is required to start using basic features."
}

output "cryptpad_ssh_connection" {
  description = "Command to SSH into the Cryptpad EC2 instance"
  value       = "ssh -i labsuser.pem ubuntu@${aws_eip.cryptpad_eip.public_ip}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for Cryptpad backups"
  value       = aws_s3_bucket.cryptpad_backup.id
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cryptpad_dashboard.dashboard_name}"
}