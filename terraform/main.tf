terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hostinger = {
      source = "hostinger/hostinger"
      # Community-tier 0.x provider: an exact pin is the only protection
      # against a breaking release (constitution non-negotiable).
      version = "= 0.1.22"
    }
  }

  # State lives in Dropbox, outside this public repo.
  # Configure with: terraform init -backend-config=backend.hcl
  # (backend.hcl is gitignored; see backend.hcl.example)
  backend "local" {}
}

# Reads HOSTINGER_API_TOKEN from the environment; never store it here.
provider "hostinger" {}
