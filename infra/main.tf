resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "case-vpc"
  }
}

#The one public subnet the case asks for
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-north-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "case-public-subnet"
  }
}

#The VPC's door to the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "case-igw"
  }
}

#Send everything that isn't local out through the gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "case-public-rt"
  }
}

#This is what actually makes the subnet public
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#Look up the latest Amazon Linux 2023 image instead of hardcoding an ID
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

#Firewall for the web server, HTTP in and anything out
resource "aws_security_group" "web" {
  name        = "case-web-sg"
  description = "Allow HTTP in and all traffic out"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound, e.g. for installing packages"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "case-web-sg"
  }
}

#The EC2 instance the case asks for
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  #Require IMDSv2, which protects the instance's credentials
  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>Deployed by Terraform via GitHub Actions</h1>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  #New AMIs come out often, so don't replace the server every time
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "case-web"
  }
}