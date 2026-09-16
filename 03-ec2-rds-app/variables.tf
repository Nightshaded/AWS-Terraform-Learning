# =============================================================
#  INPUT VARIABLES - the knobs you can turn without editing main.tf
# =============================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Prefix used to name and tag all resources"
  type        = string
  default     = "firstapp"
}

variable "vpc_cidr" {
  description = "IP range for the whole VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "IP range for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Which AZ the subnet lives in"
  type        = string
  default     = "ap-southeast-2a"
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for uploads"
  type        = string
  default     = "firstapp-uploads-jthai-tf"
}

variable "instance_type" {
  description = "EC2 instance size (t3.micro is free-tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "db_name" {
  description = "Name of the initial database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"
}

variable "db_instance_class" {
  description = "RDS instance size (db.t3.micro is free-tier eligible)"
  type        = string
  default     = "db.t3.micro"
}