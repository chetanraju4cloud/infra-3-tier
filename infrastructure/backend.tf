provider "aws" {
  region = "us-west-2"
}

resource "aws_s3_bucket" "terraform-state-storage-s3" {
    bucket = "tf-iac-remote-state-storage-s3"
    versioning {
      enabled = true
    }
    lifecycle {
      prevent_destroy = true
    }
}

resource "aws_dynamodb_table" "dynamodb-terraform-state-lock" {
  name = "terraform-state-lock-dynamo"
  hash_key = "LockID"
  read_capacity = 5
  write_capacity = 5
  attribute {
    name = "LockID"
    type = "S"
  }
}

terraform {
  backend "s3" {
    bucket               = "tf-iac-remote-state-storage-s3"
    key                  = "core.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "core/infra/env"
    dynamodb_table       = "terraform-state-lock-dynamo"
    encrypt              = true
  }
}
