variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Prefix used for naming all resources"
  type        = string
  default     = "uar-automation"
}

variable "notification_email" {
  description = "Email address that receives access review requests"
  type        = string
}
variable "review_timeout_seconds" {
  description = "How long to wait for an owner's decision before marking NO_RESPONSE"
  type        = number
  default     = 604800 # 7 days
}
variable "schedule_expression" {
  description = "When the review runs (EventBridge Scheduler syntax)"
  type        = string
  default     = "cron(0 9 1 1,4,7,10 ? *)" # 9am on the 1st of Jan, Apr, Jul, Oct
}

variable "schedule_timezone" {
  description = "Timezone the schedule runs in"
  type        = string
  default     = "Australia/Melbourne"
}

variable "revoke_tag_key" {
  description = "Only users with this tag set to 'true' can have access removed automatically"
  type        = string
  default     = "uar-auto-revoke"
}