# =============================================================
#  OUTPUTS - handy values printed after 'terraform apply'
# =============================================================

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.uptime_checker.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "schedule" {
  description = "The active check schedule"
  value       = aws_cloudwatch_event_rule.schedule.schedule_expression
}

output "monitored_sites" {
  description = "Sites currently being checked"
  value       = var.sites_to_check
}

output "next_step" {
  description = "Reminder to confirm the email subscription"
  value       = "Check your inbox and CONFIRM the SNS email subscription, or you won't get alerts!"
}