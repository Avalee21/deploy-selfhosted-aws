output "grafana_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.grafana_server.id
}

output "grafana_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.grafana_server.public_ip
}

output "grafana_url" {
  description = "URL to access Grafana"
  value       = "http://${aws_instance.grafana_server.public_ip}:3000"
}

output "grafana_login_instructions" {
  description = "Instructions to login to Grafana"
  value       = "Access Grafana at http://${aws_instance.grafana_server.public_ip}:3000 with default username 'admin' and password 'admin'. You will be prompted to change the password on first login."
}

output "grafana_ssh_connection" {
  description = "Command to SSH into the Grafana EC2 instance"
  value       = "ssh -i labsuser.pem ec2-user@${aws_instance.grafana_server.public_ip}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for Grafana storage"
  value       = aws_s3_bucket.grafana_storage.id
}

output "minio_integration_instructions" {
  description = "Instructions to view MinIO monitoring in Grafana"
  value       = "After logging into Grafana, navigate to Dashboards > Browse > AWS > MinIO Monitoring to view your MinIO metrics."
}