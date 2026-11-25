# ============================================================
# providers.tf  ·  Etapa 1: configuración del proveedor AWS
# ============================================================
# Las credenciales NO se escriben aquí. Terraform las toma de:
#   %USERPROFILE%\.aws\credentials   (Windows)
#   ~/.aws/credentials               (Linux / Mac)
# En AWS Academy esas credenciales se copian desde:
#   Learner Lab > AWS Details > AWS CLI: Show
# y vencen cada vez que termina la sesión del laboratorio.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
