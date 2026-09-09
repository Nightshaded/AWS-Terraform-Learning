provider "aws" {
  region = var.aws_region
}

# =============================================================
#  SNS - the alert channel
# =============================================================
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =============================================================
#  IAM - the role the Lambda runs with
# =============================================================

# The role the Lambda "becomes" when it runs
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lets it write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege: publish ONLY to our topic
resource "aws_iam_role_policy" "sns_publish" {
  name = "allow-sns-publish"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "sns:Publish"
      Effect   = "Allow"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}

# =============================================================
#  LAMBDA - the check logic
# =============================================================

# Zip the handler automatically - no manual zipping
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_lambda_function" "uptime_checker" {
  function_name    = "${var.project_name}-tf"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.alerts.arn
      SITES           = var.sites_to_check
      TIMEOUT_SECONDS = var.timeout_seconds
    }
  }
}

# =============================================================
#  EVENTBRIDGE - the schedule (the "cron")
# =============================================================
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.project_name}-schedule-tf"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.uptime_checker.arn
}

# Allow EventBridge to invoke the Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
