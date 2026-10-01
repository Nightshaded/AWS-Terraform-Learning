resource "aws_dynamodb_table" "access_reviews" {
  name           = "${var.project_name}-reviews"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key  = "review_id"
  range_key = "user_name"

  attribute {
    name = "review_id"
    type = "S"
  }

  attribute {
    name = "user_name"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }
}