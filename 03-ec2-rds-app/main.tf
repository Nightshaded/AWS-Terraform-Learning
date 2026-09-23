provider "aws" {
  region = var.aws_region
}
# =============================================================
#  NETWORKING — the "land" everything sits on
# =============================================================

# 1. The VPC itself — our private slice of the AWS network
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc-tf" }
}

# 2. A public subnet inside the VPC
#    map_public_ip_on_launch = true  ← the fix for the issue you hit!
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true   # instances here auto-get a public IP 🎯

  tags = { Name = "${var.project_name}-public-subnet-tf" }
}

# 3. The internet gateway — the "door" to the internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw-tf" }
}

# 4. A route table that sends internet traffic to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                    # all internet traffic...
    gateway_id = aws_internet_gateway.igw.id    # ...goes to the IGW
  }

  tags = { Name = "${var.project_name}-public-rt-tf" }
}

# 5. Associate the route table with our subnet (this is what makes it "public")
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# =============================================================
#  SECURITY GROUP — the firewall around our instance
# =============================================================

resource "aws_security_group" "web" {
  name        = "${var.project_name}-sg-tf"
  description = "Web app firewall - SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.main.id   # 🔗 must live inside our VPC

  # --- INBOUND rule 1: SSH (port 22) ---
  ingress {
    description = "SSH via EC2 Instance Connect"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = data.aws_ip_ranges.instance_connect.cidr_blocks   # auto fetched
  }

  # --- INBOUND rule 2: HTTP (port 80) ---
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- INBOUND rule 3: HTTPS (port 443) ---
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- OUTBOUND: allow all traffic out ---
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 means "any protocol"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-tf" }
}
# =============================================================
#  STORAGE — the S3 bucket for uploads
# =============================================================

resource "aws_s3_bucket" "uploads" {
  bucket = var.bucket_name   # must be globally unique

  tags = { Name = "${var.project_name}-uploads-tf" }
}

# Keep the bucket private — block all public access (secure default)
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================
#  IAM — the role the EC2 "wears" to reach S3 keylessly
# =============================================================

# 1. The role + its trust policy (WHO can assume it)
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }   # only EC2 can wear this role
    }]
  })

  tags = { Name = "${var.project_name}-ec2-role-tf" }
}

# 2. The permissions policy (WHAT the role can do) - scoped to our bucket only
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-s3-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.uploads.arn,          # the bucket itself (for ListBucket)
        "${aws_s3_bucket.uploads.arn}/*"    # objects inside it (for Put/Get)
      ]
    }]
  })
}

# 3. The instance profile — the "wrapper" that lets EC2 actually use the role
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile-tf"
  role = aws_iam_role.ec2_role.name
}
# =============================================================
#  COMPUTE — the EC2 instance (ties everything together)
# =============================================================

# Look up the latest Ubuntu 24.04 AMI automatically
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"                                 # free-tier eligible
  subnet_id              = aws_subnet.public.id                       # our public subnet
  vpc_security_group_ids = [aws_security_group.web.id]                # our firewall
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name  # keyless S3 access 🔑

  # Runs once on first boot - installs the web server
  user_data = <<-EOF
    #!/bin/bash
    apt update -y
    apt install -y nginx unzip

    # --- Install the AWS CLI v2 (official method) ---
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws

    # --- Web server setup ---
    echo "App server ready - deployed by Terraform" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = { Name = "${var.project_name}-server-tf" }
}
# Look up AWS's current EC2 Instance Connect range for our region
data "aws_ip_ranges" "instance_connect" {
  regions  = ["ap-southeast-2"]
  services = ["ec2_instance_connect"]
}

# =============================================================
#  PRIVATE SUBNETS - for the database tier (no internet access)
# =============================================================

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-southeast-2a"

  # NOTE: no map_public_ip_on_launch - this subnet stays private
  tags = { Name = "${var.project_name}-private-a-tf" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-southeast-2b"

  tags = { Name = "${var.project_name}-private-b-tf" }
}

# The DB subnet group - RDS requires subnets across 2+ AZs
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = { Name = "${var.project_name}-db-subnet-group-tf" }
}

# =============================================================
#  DATABASE SECURITY GROUP - only the web tier may connect
# =============================================================

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg-tf"
  description = "Allow MySQL from the web tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from web servers only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]   # 🌟 SG reference, not an IP!
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-db-sg-tf" }
}

# =============================================================
#  DATABASE PASSWORD - generated, never hardcoded
# =============================================================

resource "random_password" "db" {
  length  = 20
  special = true
  # RDS disallows these characters in passwords
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store it in Secrets Manager so you can retrieve it later
resource "aws_secretsmanager_secret" "db" {
  name = "${var.project_name}-db-password-tf"

  # Lets you destroy/recreate freely while learning
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    dbname   = var.db_name
  })
}
# =============================================================
#  RDS - the managed MySQL database
# =============================================================

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db-tf"

  # --- Engine ---
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class    # db.t3.micro = free tier

  # --- Storage ---
  allocated_storage     = 20                # 20 GB (free tier limit)
  max_allocated_storage = 0                 # disable autoscaling (cost control)
  storage_type          = "gp2"
  storage_encrypted     = true              # encryption at rest 🔒

  # --- Credentials ---
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result      # 🔑 from the generated secret

  # --- Networking (the important bit) ---
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false            # 🌟 NEVER expose a database
  multi_az               = false            # single AZ (cost control)

  # --- Backups & lifecycle ---
  backup_retention_period = 0               # no backups (learning only)
  skip_final_snapshot     = true            # lets you destroy cleanly
  deletion_protection     = false           # lets you destroy cleanly
  apply_immediately       = true

  tags = { Name = "${var.project_name}-db-tf" }
}
# Allow the EC2 role to read the database credentials
resource "aws_iam_role_policy" "secrets_access" {
  name = "${var.project_name}-secrets-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db.arn   # 🔒 this ONE secret only
    }]
  })
}