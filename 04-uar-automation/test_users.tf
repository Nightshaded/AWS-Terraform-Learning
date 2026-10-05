locals {
  test_users = {
    "test-alice" = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    "test-bob"   = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  }
}

resource "aws_iam_user" "test" {
  for_each = local.test_users
  name     = each.key
}

resource "aws_iam_user_policy_attachment" "test" {
  for_each   = local.test_users
  user       = aws_iam_user.test[each.key].name
  policy_arn = each.value
}