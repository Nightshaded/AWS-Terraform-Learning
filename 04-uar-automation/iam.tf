data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "collect_users" {
  name               = "${var.project_name}-collect-users-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "collect_users" {
  statement {
    sid = "ReadIamUsers"
    actions = [
      "iam:ListUsers",
      "iam:ListAttachedUserPolicies",
      "iam:ListUserPolicies",
      "iam:ListGroupsForUser"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteReviews"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.access_reviews.arn]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.collect_users.arn}:*"]
  }
}

resource "aws_iam_role_policy" "collect_users" {
  name   = "${var.project_name}-collect-users-policy"
  role   = aws_iam_role.collect_users.id
  policy = data.aws_iam_policy_document.collect_users.json
}