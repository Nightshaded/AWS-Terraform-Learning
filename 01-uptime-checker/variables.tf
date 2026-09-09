# =============================================================
#  INPUT VARIABLES - the knobs for the uptime checker
# =============================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Prefix used to name and tag resources"
  type        = string
  default     = "uptime-checker"
}

variable "alert_email" {
  description = "Email address that receives DOWN alerts"
  type        = string
  default     = "jordanthai1910@gmail.com"
}

variable "sites_to_check" {
  description = "Comma-separated list of URLs to monitor"
  type        = string
  default     = "https://n8n.jordanthai.com"
}

variable "schedule_expression" {
  description = "How often to run the check (EventBridge syntax)"
  type        = string
  default     = "rate(5 minutes)"
}

variable "timeout_seconds" {
  description = "How long to wait for each site before marking it down"
  type        = string
  default     = "10"
}

variable "lambda_timeout" {
  description = "Max seconds the Lambda can run"
  type        = number
  default     = 30
}