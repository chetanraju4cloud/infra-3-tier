###############################################################################################################################
# Platform for the 3 Tier Applications
###############################################################################################################################

#-----------------------------------------------------
# VPC
#-----------------------------------------------------

provider "aws" {
  region = var.region
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

module "vpc" {
  source           = "git::git@github.com:chetanraju4cloud/iac-aws-modules.git//modules/vpc?ref=v0.0.1"
  name             = "${var.name}-${var.environment_prefix}"
  cidr             = var.cidr
  azs              = var.azs
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets


  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  create_database_subnet_group = true
  enable_dns_hostnames         = true
  enable_dns_support           = true
  enable_nat_gateway           = true
  single_nat_gateway           = true
  tags                         = var.tags

  # VPC Endpoint for EC2
  enable_ec2_endpoint              = true
  ec2_endpoint_private_dns_enabled = true
  ec2_endpoint_security_group_ids  = [data.aws_security_group.default.id]


  # VPC endpoint for KMS
  enable_kms_endpoint              = true
  kms_endpoint_private_dns_enabled = true
  kms_endpoint_security_group_ids  = [data.aws_security_group.default.id]

  # VPC Endpoint for Secrets Manager
  enable_secretsmanager_endpoint              = true
  secretsmanager_endpoint_private_dns_enabled = true
  secretsmanager_endpoint_security_group_ids  = [data.aws_security_group.default.id]

  # VPC Endpoint for EC2 Autoscaling
  enable_ec2_autoscaling_endpoint              = true
  ec2_autoscaling_endpoint_private_dns_enabled = true
  ec2_autoscaling_endpoint_security_group_ids  = [data.aws_security_group.default.id]

  # VPC Endpoint for Elastic Load Balancing
  enable_elasticloadbalancing_endpoint              = true
  elasticloadbalancing_endpoint_private_dns_enabled = true
  elasticloadbalancing_endpoint_security_group_ids  = [data.aws_security_group.default.id]

  # VPC Endpoint for CloudWatch Logs
  enable_logs_endpoint              = true
  logs_endpoint_private_dns_enabled = true
  logs_endpoint_security_group_ids  = [data.aws_security_group.default.id]

  # Default security group - ingress/egress rules cleared to deny all
  manage_default_security_group  = true
  default_security_group_ingress = var.default_security_group_ingress
  default_security_group_egress  = var.default_security_group_egress
}

#-----------------------------------------------------
# KMS
#-----------------------------------------------------

module "cmk_key" {
  source = "git::git@github.com:chetanraju4cloud/iac-aws-modules.git//modules/kms?ref=v0.0.1"

  product_domain          = "${var.name}-${var.environment_prefix}"
  alias_name              = "${var.name}-${var.environment_prefix}"
  environment             = "${var.name}-${var.environment_prefix}"
  description             = "Key to encrypt and decrypt data"
  deletion_window_in_days = 7
  key_policy              = "${data.aws_iam_policy_document.cmk_key_policy.json}"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "cmk_key_policy" {
  statement {
    sid = "2"

    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "logs.${var.region}.amazonaws.com"
      ]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]

    resources = [
      "*",
    ]
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"


      values = [
        "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${var.name}-${var.environment_prefix}/cluster",
      ]
    }
  }
  statement {
    sid = "1"

    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
    }

    actions = [
      "kms:*",
    ]

    resources = [
      "*",
    ]
  }
}

##############################################################
# Data sources to get VPC, subnets and security group details
##############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = module.vpc.vpc_id
}

data "aws_security_group" "default" {
  vpc_id = module.vpc.vpc_id
  name   = "default"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn-ami-hvm-*-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
}

######
# Launch configuration and autoscaling group
######
module "example_asg" {
  source = "git::git@github.com:chetanraju4cloud/iac-aws-modules.git//modules/autoscaling?ref=v0.0.1"

  name = "example-with-elb"

  # Launch configuration
  #
  # launch_configuration = "my-existing-launch-configuration" # Use the existing launch configuration
  # create_lc = false # disables creation of launch configuration
  lc_name = "example-lc"

  image_id        = data.aws_ami.amazon_linux.id
  instance_type   = "t2.micro"
  security_groups = [data.aws_security_group.default.id]
  load_balancers  = [module.elb.this_elb_id]

  ebs_block_device = [
    {
      device_name           = "/dev/xvdz"
      volume_type           = "gp2"
      volume_size           = "50"
      delete_on_termination = true
    },
  ]

  root_block_device = [
    {
      volume_size = "50"
      volume_type = "gp2"
    },
  ]

  # Auto scaling group
  asg_name                  = "example-asg"
  vpc_zone_identifier       = data.aws_subnet_ids.all.ids
  health_check_type         = "EC2"
  min_size                  = 0
  max_size                  = 1
  desired_capacity          = 0
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "megasecret"
      propagate_at_launch = true
    },
  ]
}

######
# ELB
######
module "elb" {
  source = "git::git@github.com:chetanraju4cloud/iac-aws-modules.git//modules/alb/aws?ref=v0.0.1"

  name = "elb-example"

  subnets         = data.aws_subnet_ids.all.ids
  security_groups = [data.aws_security_group.default.id]
  internal        = false

  listener = [
    {
      instance_port     = "80"
      instance_protocol = "HTTP"
      lb_port           = "80"
      lb_protocol       = "HTTP"
    },
  ]

  health_check = {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = var.tags
}
