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
#test1
provider "aws" {
  profile = "default"
  region  = "us-west-2"
}

data "aws_region" "current" {}

resource "aws_instance" "card-processing-vm" {
  ami           = "ami-0ca285d4c2cda3300"
  instance_type = "t2.nano"

  tags = {
    Name = "ec2-cardprocessing-dev-${data.aws_region.current.name}-1-sn"
  }
}

