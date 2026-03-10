output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.ghost.id
}

output "alb_dns_name" {
  description = "ALB DNS name — Route 53 ALIAS records point here automatically"
  value       = aws_lb.ghost.dns_name
}

output "instance_ip" {
  description = "EC2 Elastic IP — for SSM access and troubleshooting (not used for DNS)"
  value       = aws_eip.ghost.public_ip
}

output "ghost_url" {
  description = "Configured Ghost blog URL"
  value       = var.ghost_url
}

output "ssm_connect" {
  description = "Command to open a shell on the instance without SSH"
  value       = "aws ssm start-session --target ${aws_instance.ghost.id} --region ${var.aws_region}"
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.ghost_db.arn
  sensitive   = true
}

output "log_group" {
  description = "CloudWatch log group for container logs"
  value       = aws_cloudwatch_log_group.ghost.name
}
