variable "aws_region" {
  type        = string
  description = "The AWS Region to deploy infrastructure into"
  default     = "ap-south-2" # Hyderabad Region
}

variable "vpc_cidr" {
  type        = string
  description = "The core CIDR block for the custom VPC network"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public tier subnet"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the private tier subnet"
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  type        = string
  description = "The sizing category for our isolated EC2 server"
  default     = "t3.micro"
}