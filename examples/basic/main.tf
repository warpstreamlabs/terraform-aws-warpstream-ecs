locals {
  name = "ex-warpstream-${basename(path.cwd)}"

  region = "us-east-1"
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
  }
}

module "warpstream" {
  source = "../.."

  cluster_name         = local.name
  control_plane_region = local.region

  ec2_instance_type               = "m6in.xlarge"
  ec2_instance_security_group_ids = [module.vpc.default_security_group_id]

  # List of subnet IDs to launch ESC ec2 VMs in. 
  # Subnets automatically determine which availability zones the group will reside.
  ec2_vpc_zone_identifier = module.vpc.private_subnets

  # The VPC and subnet IDs that the warpstream ECS service runs on
  # The subnets can be different then the ec2_vpc_zone_identifier
  ecs_service_vpc_id = module.vpc.vpc_id
  ecs_subnet_ids     = module.vpc.private_subnets
}
