output "vpc_id" {
  value       = aws_vpc.hyd_vpc.id
  description = "The Unique ID reference of your deployed Hyderabad custom VPC"
}

output "private_instance_id" {
  value       = aws_instance.isolated_worker.id
  description = "The AWS Instance ID of your isolated worker machine"
}

output "nat_gateway_public_ip" {
  value       = aws_eip.nat_eip.public_ip
  description = "The static exit IP address all traffic from your private subnet will present to the internet"
}