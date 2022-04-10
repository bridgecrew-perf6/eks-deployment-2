terraform {
#  backend "s3" {
#    bucket         = "<bucket-name>"
#    key            = "<terraform state key>"
#    region         = "<region>"
#    dynamodb_table = "<dynamo db table for lock>"
#  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.35.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.0.0"
    }

    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"

    }
    helm = {
      source = "hashicorp/helm"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }

  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = var.region
}




