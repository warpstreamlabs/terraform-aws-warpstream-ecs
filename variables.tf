variable "resource_prefix" {
  description = "The prefix to apply to AWS resource names"
}

variable "warpstream_agent_docker_image" {
  description = "The docker image for the warpstream agent"
  type        = string
  default     = "public.ecr.aws/warpstream-labs/warpstream_agent"
}

variable "kafka_port" {
  description = "The port that warpstream listens on for Kafka connections"
  type        = number
  default     = 9092
}

variable "warpstream_agent_version" {
  description = "The version of the warpstream agent to deploy"
  type        = string
  default     = "v731"
}

variable "warpstream_virtual_cluster_id" {
  description = "The warpstream virtual cluster ID"
  type        = string
}

variable "warpstream_agent_key_secret_manager_arn" {
  description = "The ARN of the secret manager secret version for the warpstream agent key"
  type        = string
}

variable "bucket_names" {
  description = "A list of S3 bucket names that the WarpStream agents will use"
  type        = list(string)

  validation {
    condition     = length(var.bucket_names) != 0
    error_message = "Must set at least one bucket name in 'bucket_names'"
  }

}

variable "compaction_bucket_name" {
  description = "The name of the compaction bucket for low latency clusters"
  type        = string
  default     = ""
}

variable "ecs_service_min_capacity" {
  description = "The minimum number of warpstream agent replicas to autoscale down to"
  default     = 3
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

variable "ecs_service_additional_security_group_ids" {
  description = "Security group IDs for ecs service"
  type        = list(string)
}

variable "ecs_service_additional_environment_variables" {
  description = "Additional environment variables to expose on the WarpStream ECS service"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "ecs_service_additional_iam_policies" {
  description = "Additional IAM policies to assign to the task ECS role"
  type = list(object({
    name        = string
    policy_json = string
  }))
  default = []
}

variable "ecs_log_group_retention_days" {
  description = "The number of days to retain warpstream logs in the log group"
  type        = number
  default     = 7
}
