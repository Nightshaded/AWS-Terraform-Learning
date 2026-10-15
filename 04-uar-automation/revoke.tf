data "archive_file" "revoke_access" {
  type        = "zip"
  source_file = "${path.module}/lambda/revoke_access.py"
  output_path = "${path.module}/build/revoke_access.zip"
}

resource "aws_cloudwatch_log_group" "revoke_access" {
  name              = "/aws/lambda/${var.project_name}-revoke-access"
  retention_in_days = 7
}

resource "aws_iam_role" "revoke_access" {
  name               = "${var.project_name}-revoke-access-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "revoke_access" {
  statement {
    sid = "ReadUserAccess"
    actions = [
      "iam:ListUserTags",
      "iam:ListAttachedUserPolicies",
      "iam:ListUserPolicies",
      "iam:ListGroupsForUser"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "RemoveUserPolicies"
    actions   = ["iam:DetachUserPolicy", "iam:DeleteUserPolicy"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.revoke_tag_key}"
      values   = ["true"]
    }
  }

  statement {
    sid       = "RemoveFromGroups"
    actions   = ["iam:RemoveUserFromGroup"]
    resources = ["*"]
  }

  statement {
    sid       = "RecordOutcome"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.access_reviews.arn]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.revoke_access.arn}:*"]
  }
}

resource "aws_iam_role_policy" "revoke_access" {
  name   = "${var.project_name}-revoke-access-policy"
  role   = aws_iam_role.revoke_access.id
  policy = data.aws_iam_policy_document.revoke_access.json
}

resource "aws_lambda_function" "revoke_access" {
  function_name    = "${var.project_name}-revoke-access"
  role             = aws_iam_role.revoke_access.arn
  runtime          = "python3.12"
  handler          = "revoke_access.handler"
  filename         = data.archive_file.revoke_access.output_path
  source_code_hash = data.archive_file.revoke_access.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.access_reviews.name
      REVOKE_TAG_KEY = var.revoke_tag_key
    }
  }

  depends_on = [aws_iam_role_policy.revoke_access, aws_cloudwatch_log_group.revoke_access]
}