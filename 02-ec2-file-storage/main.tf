provider "aws" {
  region = "ap-southeast-2"
}
# =============================================================
#  NETWORKING — the "land" everything sits on
# =============================================================

# 1. The VPC itself — our private slice of the AWS network
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "firstapp-vpc-tf" }
}

# 2. A public subnet inside the VPC
#    map_public_ip_on_launch = true  ← the fix for the issue you hit!
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true   # instances here auto-get a public IP 🎯

  tags = { Name = "firstapp-public-subnet-tf" }
}

# 3. The internet gateway — the "door" to the internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "firstapp-igw-tf" }
}

# 4. A route table that sends internet traffic to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                    # all internet traffic...
    gateway_id = aws_internet_gateway.igw.id    # ...goes to the IGW
  }

  tags = { Name = "firstapp-public-rt-tf" }
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
  name        = "firstapp-sg-tf"
  description = "Web app firewall - SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.main.id   # 🔗 must live inside our VPC

  # --- INBOUND rule 1: SSH (port 22) ---
  ingress {
    description = "SSH via EC2 Instance Connect"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["13.239.158.0/29"]   # AWS Instance Connect range (Sydney) - tighten later
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

  tags = { Name = "firstapp-sg-tf" }
}
# =============================================================
#  STORAGE — the S3 bucket for uploads
# =============================================================

resource "aws_s3_bucket" "uploads" {
  bucket = "firstapp-uploads-jthai-tf"   # must be globally unique

  tags = { Name = "firstapp-uploads-tf" }
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
  name = "firstapp-ec2-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }   # only EC2 can wear this role
    }]
  })

  tags = { Name = "firstapp-ec2-role-tf" }
}

# 2. The permissions policy (WHAT the role can do) - scoped to our bucket only
resource "aws_iam_role_policy" "s3_access" {
  name = "firstapp-s3-access"
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
  name = "firstapp-ec2-profile-tf"
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
    apt install -y nginx
    echo "App server ready - deployed by Terraform" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = { Name = "firstapp-server-tf" }
}