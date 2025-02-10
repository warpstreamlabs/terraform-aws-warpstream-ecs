variable "cluster_name" {
  description = "The warpstream cluster name"
}

variable "control_plane_region" {
  description = "The region of the warpstream control plane"
}

variable "ec2_instance_type" {
  description = "The isntance type for ec2 ecs instances"
}

variable "ec2_vpc_zone_identifier" {
  description = "List of subnet IDs to launch ec2 ecs instances in."
  type        = list(string)
}

variable "ec2_instance_security_group_ids" {
  description = "Security group IDs for ec2 ecs instances"
  type        = list(string)
}

variable "ecs_service_vpc_id" {
  description = "The VPC ID that the ECS service should live on"
}

variable "ecs_subnet_ids" {
  description = "Subnets associated with the warpstream service"
  type        = list(string)
}
