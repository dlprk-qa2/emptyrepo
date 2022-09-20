terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }


        pgp = {
      source = "ekristen/pgp"
    }

  }

  required_version = ">= 0.14.9"
}
#test2324
provider "aws" {
  profile = "default"
  region  = "us-west-2"
}

data "aws_region" "current" {}

resource "aws_instance" "card-processing-vmI" {
  ami           = "ami-0ca285d4c2cda3300"
  instance_type = "t2.nano"

  tags = {
    Name = "ec2-cardprocessing-dev-${data.aws_region.current.name}-1-sn"
  }
}


##### IAM role to assign to EC2 instance(s), to demonstrate CIEM capabilities:

resource "aws_iam_role" "machine-storage-access" {
  name = "machine-storage-access"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
      env = "dev"
  }
}


resource "aws_iam_instance_profile" "storage-access-profile" {
  name = "storage-access-profile"
  role = "${aws_iam_role.machine-storage-access.name}"
}


resource "aws_iam_role_policy" "storage-access-policy" {
  name = "storage-access-policy"
  role = "${aws_iam_role.machine-storage-access.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}


resource "aws_instance" "cardprocessing-frontend" {
  ami = "ami-0ca285d4c2cda3300"
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.storage-access-profile.name}"

    tags = {
    Name = "ec2-cardprocessingfrontend-dev-${data.aws_region.current.name}-1"
  }
}


resource "aws_instance" "cardprocessing-nodejs-frontend" {
  ami = "ami-0c574ce8ee8127ce0"
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.storage-access-profile.name}"

    tags = {
    Name = "ec2-cardprocessingnodejsfrontend-dev-${data.aws_region.current.name}-1"
  }
}





resource "aws_iam_user" "developer-admin" {
  name = "dev-admin"
 # path = "/system/"

  tags = {
    env = "dev"
  }
}

resource "aws_iam_access_key" "developer-key" {
  user = aws_iam_user.developer-admin.name
}

resource "aws_iam_user_policy" "developer_policy" {
  name = "developer-policy"
  user = aws_iam_user.developer-admin.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}



locals {
  users = {
    "john.doe" = {
      name  = "John Smith"
      email = "john.smith@safemarch.com"
    },
    "anna.klein" = {
        name = "Anna Klein"
        email = "anna.klein@safemarch.com"
    } 
  }
}


resource "aws_iam_user_policy" "user_policy" {
  for_each = local.users

 name = "user-policy"
  user = each.key

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_user" "user" {
  for_each = local.users

  name          = each.key
  force_destroy = false
}

resource "aws_iam_access_key" "user_access_key" {
  for_each = local.users
  
  user       = each.key
  depends_on = [aws_iam_user.user]
}

resource "pgp_key" "user_login_key" {
  for_each = local.users

  name    = each.value.name
  email   = each.value.email
  comment = "PGP Key for ${each.value.name}"
}

resource "aws_iam_user_login_profile" "user_login" {
  for_each = local.users

  user                    = each.key
  pgp_key                 = pgp_key.user_login_key[each.key].public_key_base64
  password_reset_required = true

  depends_on = [aws_iam_user.user, pgp_key.user_login_key]
}

data "pgp_decrypt" "user_password_decrypt" {
  for_each = local.users

  ciphertext          = aws_iam_user_login_profile.user_login[each.key].encrypted_password
  ciphertext_encoding = "base64"
  private_key         = pgp_key.user_login_key[each.key].private_key
}

output "credentials" {
  value = {
    for k, v in local.users : k => {
      "key"      = aws_iam_access_key.user_access_key[k].id
      "secret"   = aws_iam_access_key.user_access_key[k].secret
      "password" = data.pgp_decrypt.user_password_decrypt[k].plaintext
    }
  }
  sensitive = true
}


##### Administrator access - AWS managed policy  - resources:

resource "aws_iam_group" "dev-admins" {
  name = "dev-admins"
}


data "aws_iam_policy" "AdministratorAccess" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "dev-admins-policy-attachment" {
  group      = aws_iam_group.dev-admins.name
  policy_arn = "${data.aws_iam_policy.AdministratorAccess.arn}"
}




resource "aws_iam_group_membership" "admins" {
  name = "dev-admins-group-membership"


    for_each = local.users
    users       = [each.key]


  

  group = aws_iam_group.dev-admins.name
}



##### EC2 instance behing load balancer (ELB):




module "elb_example_complete" {
  source  = "terraform-aws-modules/elb/aws//examples/complete"
  version = "3.0.1"
}

module "vpc_example_complete-vpc" {
  source  = "terraform-aws-modules/vpc/aws//examples/complete-vpc"
  version = "3.14.4"
}
module "iam_example_iam-account" {
  source  = "terraform-aws-modules/iam/aws//examples/iam-account"
  version = "5.4.0"
}
module "security-group_example_complete" {
  source  = "terraform-aws-modules/security-group/aws//examples/complete"
  version = "4.13.0"
}
module "eks_example_complete" {
  source  = "terraform-aws-modules/eks/aws//examples/complete"
  version = "18.29.0"
}
module "s3-bucket_example_complete" {
  source  = "terraform-aws-modules/s3-bucket/aws//examples/complete"
  version = "3.4.0"
}
module "rds_example_complete-mssql" {
  source  = "terraform-aws-modules/rds/aws//examples/complete-mssql"
  version = "5.1.0"
}
  

##### EC2 instance with GPU to trigger crypto mining threat: 



resource "aws_instance" "crypto-miner" {
  ami           = "ami-0ca285d4c2cda3300"
  instance_type = "p3.2xlarge"

  tags = {
    Name = "CryptoMiner"
  }
}
