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