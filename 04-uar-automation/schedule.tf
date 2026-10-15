data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project_name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.uar.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${var.project_name}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule" "quarterly" {
  name                         = "${var.project_name}-quarterly"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.uar.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}