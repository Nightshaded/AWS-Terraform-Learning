output "dynamodb_table_name" {
  value = aws_dynamodb_table.access_reviews.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.review_requests.arn
}
output "collect_users_function" {
  value = aws_lambda_function.collect_users.function_name
}
output "state_machine_arn" {
  value = aws_sfn_state_machine.uar.arn
}

output "decision_url" {
  value = aws_lambda_function_url.record_decision.function_url
}