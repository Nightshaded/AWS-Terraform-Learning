data "archive_file" "collect_users" {
  type        = "zip"
  source_file = "${path.module}/lambda/collect_users.py"
  output_path = "${path.module}/build/collect_users.zip"
}

resource "aws_cloudwatch_log_group" "collect_users" {
  name              = "/aws/lambda/${var.project_name}-collect-users"
  retention_in_days = 7
}

resource "aws_lambda_function" "collect_users" {
  function_name    = "${var.project_name}-collect-users"
  role             = aws_iam_role.collect_users.arn
  runtime          = "python3.12"
  handler          = "collect_users.handler"
  filename         = data.archive_file.collect_users.output_path
  source_code_hash = data.archive_file.collect_users.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.access_reviews.name
    }
  }

  depends_on = [
    aws_iam_role_policy.collect_users,
    aws_cloudwatch_log_group.collect_users
  ]
}