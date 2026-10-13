# ---------- request_review ----------
data "archive_file" "request_review" {
  type        = "zip"
  source_file = "${path.module}/lambda/request_review.py"
  output_path = "${path.module}/build/request_review.zip"
}

resource "aws_cloudwatch_log_group" "request_review" {
  name              = "/aws/lambda/${var.project_name}-request-review"
  retention_in_days = 7
}

resource "aws_iam_role" "request_review" {
  name               = "${var.project_name}-request-review-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "request_review" {
  statement {
    sid       = "ReadReview"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.access_reviews.arn]
  }
  statement {
    sid       = "SendEmail"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.review_requests.arn]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.request_review.arn}:*"]
  }
}

resource "aws_iam_role_policy" "request_review" {
  name   = "${var.project_name}-request-review-policy"
  role   = aws_iam_role.request_review.id
  policy = data.aws_iam_policy_document.request_review.json
}

resource "aws_lambda_function" "request_review" {
  function_name    = "${var.project_name}-request-review"
  role             = aws_iam_role.request_review.arn
  runtime          = "python3.12"
  handler          = "request_review.handler"
  filename         = data.archive_file.request_review.output_path
  source_code_hash = data.archive_file.request_review.output_base64sha256
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.access_reviews.name
      TOPIC_ARN    = aws_sns_topic.review_requests.arn
      DECISION_URL = aws_lambda_function_url.record_decision.function_url
    }
  }

  depends_on = [aws_iam_role_policy.request_review, aws_cloudwatch_log_group.request_review]
}

# ---------- record_decision ----------
data "archive_file" "record_decision" {
  type        = "zip"
  source_file = "${path.module}/lambda/record_decision.py"
  output_path = "${path.module}/build/record_decision.zip"
}

resource "aws_cloudwatch_log_group" "record_decision" {
  name              = "/aws/lambda/${var.project_name}-record-decision"
  retention_in_days = 7
}

resource "aws_iam_role" "record_decision" {
  name               = "${var.project_name}-record-decision-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "record_decision" {
  statement {
    sid       = "UpdateReview"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.access_reviews.arn]
  }
  statement {
    sid       = "ResumeWorkflow"
    actions   = ["states:SendTaskSuccess", "states:SendTaskFailure"]
    resources = ["*"]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.record_decision.arn}:*"]
  }
}

resource "aws_iam_role_policy" "record_decision" {
  name   = "${var.project_name}-record-decision-policy"
  role   = aws_iam_role.record_decision.id
  policy = data.aws_iam_policy_document.record_decision.json
}

resource "aws_lambda_function" "record_decision" {
  function_name    = "${var.project_name}-record-decision"
  role             = aws_iam_role.record_decision.arn
  runtime          = "python3.12"
  handler          = "record_decision.handler"
  filename         = data.archive_file.record_decision.output_path
  source_code_hash = data.archive_file.record_decision.output_base64sha256
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.access_reviews.name
    }
  }

  depends_on = [aws_iam_role_policy.record_decision, aws_cloudwatch_log_group.record_decision]
}

resource "aws_lambda_function_url" "record_decision" {
  function_name      = aws_lambda_function.record_decision.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "record_decision_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.record_decision.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}