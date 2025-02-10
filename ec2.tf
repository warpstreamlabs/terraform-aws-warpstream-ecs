data "aws_iam_policy_document" "ec2_ecs" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_ecs" {
  name               = "${var.cluster_name}-ecs"
  assume_role_policy = data.aws_iam_policy_document.ec2_ecs.json
}

# TODO: we probably shouldn't be giving full access
resource "aws_iam_role_policy_attachment" "ec2_ecs_ecs_full_access" {
  role       = aws_iam_role.ec2_ecs.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# TODO: we probably shouldn't be giving full access
resource "aws_iam_role_policy_attachment" "ec2_ecs_cloudwatchlogs_full_access" {
  role       = aws_iam_role.ec2_ecs.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_instance_profile" "ec2_ecs" {
  name = "${var.cluster_name}-ecs"
  role = aws_iam_role.ec2_ecs.name
}

data "aws_ec2_instance_type" "ec2" {
  instance_type = var.ec2_instance_type
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html#ecs-optimized-ami-linux
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended"
}

resource "aws_launch_template" "ec2_ecs" {
  name = "${var.cluster_name}-ecs"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = data.aws_ec2_instance_type.ec2.instance_type

  user_data = base64encode(<<EOT
#!/bin/bash

echo ECS_CLUSTER=${aws_ecs_cluster.ecs.name} >> /etc/ecs/ecs.config

EOT
  )

  vpc_security_group_ids = var.ec2_instance_security_group_ids

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_ecs.arn
  }
}

resource "aws_autoscaling_group" "ec2_ecs" {
  name = "${var.cluster_name}-ecs"

  health_check_grace_period = 30
  health_check_type         = "EC2"

  vpc_zone_identifier = var.ec2_vpc_zone_identifier

  launch_template {
    name    = aws_launch_template.ec2_ecs.name
    version = aws_launch_template.ec2_ecs.latest_version
  }

  max_size = 30 # TODO: make this configurable
  min_size = 3

  protect_from_scale_in = true

  tag {
    key                 = "AmazonECSManaged"
    propagate_at_launch = true
    value               = ""
  }
}
