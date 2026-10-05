output "dynamodb_table_name" {
  value = aws_dynamodb_table.access_reviews.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.review_requests.arn
}
output "collect_users_function" {
  value = aws_lambda_function.collect_users.function_name
}