# ==========================================
# 1. THE CUSTOM VPC NETWORK (Hyderabad)
# ==========================================
resource "aws_vpc" "hyd_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "hyd-custom-vpc"
  }
}

# ==========================================
# 2. SUBSETS (1 Public, 1 Private)
# ==========================================
# We use data collection to dynamically map the first available Availability Zone in Hyderabad (ap-south-2a)
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.hyd_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true # Automatically assigns public IPs to resources here

  tags = {
    Name = "hyd-public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.hyd_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "hyd-private-subnet"
  }
}

# ==========================================
# 3. INTERNET GATEWAY (IGW)
# ==========================================
resource "aws_internet_gateway" "hyd_igw" {
  vpc_id = aws_vpc.hyd_vpc.id

  tags = {
    Name = "hyd-vpc-igw"
  }
}

# ==========================================
# 4. ROUTE TABLES
# ==========================================
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.hyd_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hyd_igw.id # Connects public routing up to the internet
  }

  tags = {
    Name = "hyd-public-route-table"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.hyd_vpc.id

  tags = {
    Name = "hyd-private-route-table"
  }
}

# ==========================================
# 5. SUBNET ASSOCIATIONS
# ==========================================
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# ==========================================
# 6. ELASTIC IP & NAT GATEWAY (Deploys in Public Subnet)
# ==========================================
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.hyd_igw]

  tags = {
    Name = "hyd-nat-eip"
  }
}

resource "aws_nat_gateway" "hyd_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id # Must sit in the public subnet to reach the IGW

  tags = {
    Name = "hyd-nat-gateway"
  }

  depends_on = [aws_internet_gateway.hyd_igw]
}

# ==========================================
# 7. NAT GATEWAY ROUTE IN PRIVATE ROUTE TABLE
# ==========================================
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.hyd_nat.id
}

# ==========================================
# 8. SECURITY GROUPS (SSH & HTTP)
# ==========================================
resource "aws_security_group" "instance_sg" {
  name        = "hyd-instance-security-group"
  description = "Controls incoming and outgoing resource traffic layers"
  vpc_id      = aws_vpc.hyd_vpc.id

  ingress {
    description = "Allow inbound SSH connection loops"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In production, restrict this to your specific IP address!
  }

  ingress {
    description = "Allow basic inbound HTTP web traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic via NAT Gateway network pathways"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Represents all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hyd-ec2-security-group"
  }
}

# ==========================================
# 9. IAM ROLE WITH SSM PERMISSIONS
# ==========================================
# Creates the base Identity Execution Profile
resource "aws_iam_role" "ssm_role" {
  name = "hyd-ec2-ssm-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attaches the AWS managed policy for core Systems Manager operation
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Bridges the IAM configuration block over into an EC2 hardware instance profile container
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "hyd-ec2-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

# ==========================================
# 10. EC2 INSTANCE DEPLOYED IN PRIVATE SUBNET
# ==========================================
# Dynamically pulls the latest stable Amazon Linux 2023 AMI image reference
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_instance" "isolated_worker" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  # Links the SSM policy wrapper directly to the server core
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  tags = {
    Name = "Hyd-Private-Worker-EC2"
  }
}