resource "aws_sns_topic" "review_requests" {
  name = "${var.project_name}-review-requests"
}

resource "aws_sns_topic_subscription" "owner_email" {
  topic_arn = aws_sns_topic.review_requests.arn
  protocol  = "email"
  endpoint  = var.notification_email
}