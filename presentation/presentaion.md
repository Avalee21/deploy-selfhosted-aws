# AWS Cloud-Based Collaborative Environment

## Introduction

Today I'm presenting our cloud-based collaborative environment deployed in AWS Academy. This architecture provides a comprehensive solution for object storage, collaborative document editing, and monitoring.

## What We've Deployed

We've implemented three core services:

1. **MinIO** - S3-compatible object storage system
2. **Cryptpad** - Zero-knowledge collaborative document editor
3. **Grafana** - Comprehensive monitoring platform

## Architecture Overview

Our solution is built on a shared VPC spanning two availability zones with the following components:

- MinIO deployed across two AZs with a load balancer for high availability
- Cryptpad on a dedicated instance with persistent storage
- Grafana providing unified monitoring for all services
- S3 buckets for backups and persistent configurations
- CloudWatch integration for custom metrics and monitoring

## Value and Usage

### MinIO

- **Value**: Provides S3-compatible API while maintaining control of our infrastructure
- **Usage**: Object storage accessed via API endpoint or console.
- **Storage**: 30GB EBS volumes per server, providing 60GB total distributed storage

### Cryptpad

- **Value**: Enables secure, private collaborative document editing with end-to-end encryption
- **Usage**: Real-time collaboration on documents, spreadsheets, and presentations without user accounts
- **Storage**: 20GB persistent EBS volume with S3 backup mechanism

### Grafana

- **Value**: Centralizes monitoring with rich visualization of all infrastructure metrics
- **Usage**: Pre-configured dashboards for both MinIO and Cryptpad performance metrics
- **Integration**: Seamless connection to CloudWatch metrics for comprehensive visibility

## Why This Design?

1. **High Availability**: Multi-AZ deployment for MinIO ensures service continuity
2. **Resource Efficiency**: Shared infrastructure maximizes limited AWS Academy resources
3. **Data Protection**: Persistent EBS volumes and S3 backups safeguard critical data
4. **Security Isolation**: Proper subnet and security group segmentation
5. **Comprehensive Monitoring**: Full visibility into system and application health

## Implementation Considerations

- We selected t3.micro instances for MinIO and Grafana, with t3.small for Cryptpad to support Node.js
- EBS volumes provide persistent storage, surviving instance termination
- Docker containers simplify deployment and maintenance of MinIO
- CloudWatch custom metrics deliver detailed application-specific monitoring

## Conclusion

This architecture demonstrates how to build a robust, multi-service cloud environment even within the constraints of AWS Academy, providing:

- Highly available object storage
- Secure collaborative document editing
- Comprehensive monitoring and visualization
- Strong data protection through multiple backup mechanisms
