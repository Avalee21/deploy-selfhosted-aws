#!/bin/bash
# Setup script for Terraform and AWS CLI in AWS Academy environment
# Make it executable: chmod +x setup.sh

# Exit on error
set -e

echo "===== Installing Terraform and AWS CLI for AWS Academy ====="

# Update package lists
echo "Updating package lists..."
sudo apt-get update

# Install dependencies
echo "Installing dependencies..."
sudo apt-get install -y gnupg software-properties-common curl unzip

# Add Terraform repository
echo "Adding Terraform repository..."
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update package lists with new repository
sudo apt-get update

# Install Terraform
echo "Installing Terraform..."
sudo apt-get install -y terraform

# Verify Terraform installation
echo "Terraform version:"
terraform --version

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

# Verify AWS CLI installation
echo "AWS CLI version:"
aws --version

echo "===== Setup Complete ====="
echo "Terraform and AWS CLI have been installed successfully."
echo ""
echo "NOTE: You do not need to run 'aws configure' in AWS Academy."
echo "The LabRole and LabInstanceProfile provide necessary permissions."
echo ""
echo "You can now run Terraform commands to deploy your infrastructure:"
echo "terraform init"
echo "terraform plan"
echo "terraform apply"