variable "cluster_name" {
  description = "The warpstream cluster name"
}

variable "warpstream_agent_version" {
  description = "The version of the warpstream agent to deploy"
  type        = string
  default     = "v625"
}

variable "ecs_service_max_capacity" {
  description = "The maximum number of warpstream agent replicas to autoscale up to"
  default     = 30
}

variable "control_plane_region" {
  description = "The region of the warpstream control plane"
}

variable "ec2_instance_type" {
  description = "The instance type for ec2 ecs instances"
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
  description = "Subnets associated with the warpstream ecs service"
  type        = list(string)
}

variable "disable_default_warpstream_agent_egress" {
  description = "Disable the default egress rule allowing the WarpStream Agent to egress to 0.0.0.0/0"
  type        = bool
  default     = false
}
