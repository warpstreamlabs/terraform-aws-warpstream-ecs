locals {
  name = "ex-warpstream-${basename(path.cwd)}"

  region = "us-east-1"
}

variable "warpstream_virtual_cluster_id" {
  description = "The warpstream virtual cluster id"
  type        = string
}

variable "warpstream_agent_key" {
  description = "The agent key for the warpstream cluster"
  type        = string
  sensitive   = true
}

provider "aws" {
  region = local.region
}

# Creating a VPC for this example, you can bring your own VPC
# if you already have one and don't need to use the one created here.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.18.1"

  name = local.name

  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # Default security group in the VPC to allow all egressing.
  default_security_group_egress = [
    {
      description = "Allow all egress"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

# It is highly recommended to create a S3 Gateway endpoint in your VPC.
# This is prevent S3 network traffic from egressing over your NAT Gateway and increasing costs.
module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "5.18.1"

  vpc_id = module.vpc.vpc_id

  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"

  # Security group for the endpoints.
  # We are allowing everything in the VPC to connect to the S3 endpoint.
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = local.name }
    },
    # Used for S3 Express for lower latency configurations
    # Ref: https://docs.warpstream.com/warpstream/byoc/advanced-agent-deployment-options/low-latency-clusters
    s3express = {
      service         = "s3express"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = local.name }
    }
  }
}

# Creating a security group to allow things in the VPC
# to connect to the WarpStream Agents.
resource "aws_security_group" "warpstream-connect" {
  name        = "${local.name}-connect"
  description = "Allow applications in the the VPC to connect to the WarpStream Kafka Port"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "allow_application_to_agent_kafka" {
  security_group_id = aws_security_group.warpstream-connect.id
  description       = "Allow applications to Agent Kafka Communication"

  ip_protocol = "tcp"
  from_port   = 9092
  to_port     = 9092
  cidr_ipv4   = "10.0.0.0/16"
}


# Store the WarpStream Agent Key in AWS Secret Manager
resource "aws_secretsmanager_secret" "warpstream_agent_key" {
  name_prefix = "${local.name}-agent-key"
}

resource "aws_secretsmanager_secret_version" "warpstream_agent_key" {
  secret_id     = aws_secretsmanager_secret.warpstream_agent_key.id
  secret_string = var.warpstream_agent_key
}

module "warpstream" {
  source = "../.."

  depends_on = [module.vpc, module.endpoints]

  resource_prefix      = local.name
  control_plane_region = local.region

  warpstream_virtual_cluster_id           = var.warpstream_virtual_cluster_id
  warpstream_agent_key_secret_manager_arn = aws_secretsmanager_secret_version.warpstream_agent_key.arn

  # We recommend network optimized instances with a minimum of 4 vCPUs and 16gb Memory to get the best performance.
  # We have also tested with Graviton3+ (m7g) and found decent performance. 
  # The ECS tasks assume 1:4 vCPU to Memory ratio with 1 core and 4gb of ram left to the host OS.
  ec2_instance_type = "m6in.xlarge"

  # Add the default VPC security group to the ECS EC2 instances.
  ec2_instance_security_group_ids = [module.vpc.default_security_group_id]

  # List of subnet IDs to launch ecs ec2 VMs in. 
  # Subnets automatically determine which availability zones the ec2 group will reside.
  ec2_vpc_zone_identifier = module.vpc.private_subnets

  # The VPC that the warpstream ECS service runs on
  ecs_service_vpc_id = module.vpc.vpc_id

  # List of subnet IDs to launch the ecs service in. 
  # The subnets can be different then the ec2_vpc_zone_identifier
  # Subnets automatically determine which availability zones the ecs service will reside.
  ecs_subnet_ids = module.vpc.private_subnets

  # Specifying the security group to allow things in the VPC to connect to WarpStream agents.
  ecs_service_additional_security_group_ids = [aws_security_group.warpstream-connect.id]

  bucket_names           = aws_s3_directory_bucket.s3_express_buckets[*].bucket
  compaction_bucket_name = aws_s3_bucket.compaction_bucket.bucket

  # You can lower latency even more by setting the WARPSTREAM_BATCH_TIMEOUT environment variable
  # Ref: https://docs.warpstream.com/warpstream/byoc/advanced-agent-deployment-options/low-latency-clusters#batch-timeout
  # ecs_service_additional_environment_variables = [{
  #   name  = "WARPSTREAM_BATCH_TIMEOUT"
  #   value = "50ms"
  # }]
}
