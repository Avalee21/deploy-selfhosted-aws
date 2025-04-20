# AWS Cloud-Based Collaborative Environment

A comprehensive cloud infrastructure solution providing object storage, collaborative document editing, and monitoring capabilities within the AWS Academy environment.

## Architecture Overview

![Architecture Diagram](./presentation/architecture.svg)

## Components

This project deploys three core services in a shared VPC across multiple availability zones:

### 1. MinIO
- **Description**: S3-compatible object storage system deployed across two AZs
- **Features**:
  - Docker-based deployment for easy management
  - Application Load Balancer for high availability
  - Web-based administration console
  - CloudWatch metrics integration
  - 60GB of distributed storage (30GB per node)

### 2. CryptPad
- **Description**: Zero-knowledge collaborative document editor with end-to-end encryption
- **Features**:
  - Real-time document collaboration
  - No user accounts required for basic usage
  - Support for documents, spreadsheets, presentations, and more
  - Automated S3 backups
  - Persistent EBS storage

### 3. Grafana
- **Description**: Comprehensive monitoring dashboard for visualization
- **Features**:
  - Pre-configured dashboards for MinIO and CryptPad
  - CloudWatch integration
  - S3 backup for configurations
  - Real-time metric visualization

## Technical Implementation

### Network Architecture
- Shared VPC with segmented subnets for each service
- Public-facing load balancer for MinIO
- Security groups restricting access to specific ports
- Internet Gateway for external connectivity

### Storage Architecture
- Persistent EBS volumes for all services
- S3 buckets for backups and configurations
- Multi-AZ deployment for MinIO storage nodes

### Monitoring
- CloudWatch custom metrics
- Grafana dashboards for visualization
- Custom scripts for metric collection

## Deployment Instructions

### Prerequisites
- AWS Academy environment access
- Terraform installed with setup.sh
- AWS CLI configured with AWS Academy credentials

### Deployment Steps

1. **Clone this repository**
   ```
   git clone https://github.com/your-username/aws-collaborative-env.git
   cd aws-collaborative-env
   ```

2. **Deploy MinIO (foundation infrastructure)**
   ```
   cd minio
   terraform init
   terraform apply
   ```

3. **Deploy CryptPad**
   ```
   cd ../cryptpad
   terraform init
   terraform apply
   ```

4. **Deploy Grafana**
   ```
   cd ../grafana
   terraform init
   terraform apply
   ```

5. **Verify deployment**
   - MinIO console: http://[load-balancer-dns]:9001 (credentials: minio/minio123)
   - CryptPad: http://[cryptpad-ip]:3000
   - Grafana: http://[grafana-ip]:3000 (default credentials: admin/admin)

## Usage Guide

### MinIO Usage
- Access the MinIO console via the load balancer DNS on port 9001
- Create buckets and manage objects through the web console
- Use S3-compatible tools and SDKs for programmatic access

### CryptPad Usage
- Access CryptPad via the elastic IP on port 3000
- Create new documents by clicking the "+" icon
- Share document links for collaboration
- No login required for basic usage

### Grafana Usage
- Access Grafana via the instance IP on port 3000
- Login with default credentials (admin/admin)
- View pre-configured dashboards for MinIO and CryptPad
- Create custom dashboards as needed

## Important Considerations

### AWS Academy Limitations
- Limited to us-east-1 region
- Limited instance types (t2/t3.micro, t3.small)
- Environment cleaned up at session end (addressed via persistent storage)
- Pre-configured IAM roles (LabRole)

### Security Considerations
- Default credentials should be changed in production
- Security groups are configured for demonstration purposes
- End-to-end encryption provided by CryptPad for document security

## Maintenance Scripts

The repository includes maintenance scripts for each service:

- `minio.sh`: Setup and metrics collection for MinIO
- `cryptpad.sh`: Metrics collection and status checking for CryptPad

Run these scripts on the respective instances to ensure proper configuration and monitoring.

## Backup and Recovery

- MinIO data is replicated across two availability zones
- CryptPad has automated daily backups to S3
- Grafana configurations are stored in S3
- EBS volumes persist even if instances are terminated

## Acknowledgments

- AWS Academy for providing the cloud environment
- MinIO, CryptPad, and Grafana open-source projects
- Terraform for infrastructure as code capabilities