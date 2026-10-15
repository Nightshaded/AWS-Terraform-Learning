data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name               = "${var.project_name}-state-machine-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "state_machine" {
  statement {
    sid     = "InvokeLambdas"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.collect_users.arn,
      "${aws_lambda_function.collect_users.arn}:*",
      aws_lambda_function.request_review.arn,
      "${aws_lambda_function.request_review.arn}:*",
      aws_lambda_function.revoke_access.arn,
      "${aws_lambda_function.revoke_access.arn}:*",
    ]
  }
  statement {
    sid       = "MarkNoResponse"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.access_reviews.arn]
  }
  statement {
    sid       = "SendSummary"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.review_requests.arn]
  }
}

resource "aws_iam_role_policy" "state_machine" {
  name   = "${var.project_name}-state-machine-policy"
  role   = aws_iam_role.state_machine.id
  policy = data.aws_iam_policy_document.state_machine.json
}

resource "aws_sfn_state_machine" "uar" {
  name     = "${var.project_name}-workflow"
  role_arn = aws_iam_role.state_machine.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Quarterly User Access Review"
    StartAt = "CollectUsers"
    States = {

      CollectUsers = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.collect_users.arn
          "Payload.$"  = "$"
        }
        ResultSelector = {
          "review_id.$" = "$.Payload.review_id"
          "users.$"     = "$.Payload.users"
        }
        Next = "ReviewEachUser"
      }

      ReviewEachUser = {
        Type           = "Map"
        ItemsPath      = "$.users"
        MaxConcurrency = 5
        ItemSelector = {
          "user_name.$" = "$$.Map.Item.Value"
          "review_id.$" = "$.review_id"
        }
        ItemProcessor = {
          ProcessorConfig = { Mode = "INLINE" }
          StartAt         = "RequestReview"
          States = {

            RequestReview = {
              Type           = "Task"
              Resource       = "arn:aws:states:::lambda:invoke.waitForTaskToken"
              TimeoutSeconds = var.review_timeout_seconds
              Parameters = {
                FunctionName = aws_lambda_function.request_review.arn
                Payload = {
                  "user_name.$"  = "$.user_name"
                  "review_id.$"  = "$.review_id"
                  "task_token.$" = "$$.Task.Token"
                }
              }
              ResultPath = "$.result"
              Catch = [{
                ErrorEquals = ["States.Timeout"]
                ResultPath  = "$.error"
                Next        = "MarkNoResponse"
              }]
              Next = "CheckDecision"
            }

            CheckDecision = {
              Type = "Choice"
              Choices = [{
                Variable     = "$.result.decision"
                StringEquals = "REVOKED"
                Next         = "RevokeAccess"
              }]
              Default = "ReviewDone"
            }

            RevokeAccess = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.revoke_access.arn
                Payload = {
                  "user_name.$" = "$.user_name"
                  "review_id.$" = "$.review_id"
                }
              }
              ResultPath = null
              Next       = "ReviewDone"
            }

            ReviewDone = {
              Type = "Pass"
              Parameters = {
                "user_name.$" = "$.user_name"
                "decision.$"  = "$.result.decision"
              }
              End = true
            }

            MarkNoResponse = {
              Type     = "Task"
              Resource = "arn:aws:states:::dynamodb:updateItem"
              Parameters = {
                TableName = aws_dynamodb_table.access_reviews.name
                Key = {
                  review_id = { "S.$" = "$.review_id" }
                  user_name = { "S.$" = "$.user_name" }
                }
                UpdateExpression          = "SET decision = :d"
                ExpressionAttributeValues = { ":d" = { S = "NO_RESPONSE" } }
              }
              ResultPath = null
              Next       = "NoResponseResult"
            }

            NoResponseResult = {
              Type = "Pass"
              Parameters = {
                "user_name.$" = "$.user_name"
                decision      = "NO_RESPONSE"
              }
              End = true
            }
          }
        }
        ResultPath = "$.decisions"
        Next       = "SendSummary"
      }

      SendSummary = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.review_requests.arn
          "Subject.$" = "States.Format('Access review {} complete', $.review_id)"
          "Message.$" = "States.Format('Access review {} is complete. Results: {}', $.review_id, States.JsonToString($.decisions))"
        }
        End = true
      }
    }
  })

  depends_on = [aws_iam_role_policy.state_machine]
}