# ============================================================================
# providers.tf — Provider Configuration
# ============================================================================
#
# WHAT IS A PROVIDER?
# A provider is a plugin that tells Terraform how to talk to a specific
# platform (Proxmox, AWS, Azure, etc.). Each provider offers "resources"
# (things you can create) and "data sources" (things you can look up).
#
# The bpg/proxmox provider is the modern, actively maintained provider for
# Proxmox VE. It replaced the older Telmate/proxmox provider.
# Docs: https://registry.terraform.io/providers/bpg/proxmox/latest/docs
# ============================================================================

# ---------------------------------------------------------------------------
# terraform block — global Terraform settings
# ---------------------------------------------------------------------------
# The `required_providers` block pins the provider name, source, and version.
# The "~>" operator means "compatible with" — it allows patch updates
# (e.g. 0.78.1) but not minor/major bumps (e.g. 0.79.0 or 1.0.0).
# This protects you from breaking changes when running `terraform init`.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.5.0" # Minimum Terraform CLI version

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.0" # Pin to a known-good version range
    }
  }
}

# ---------------------------------------------------------------------------
# provider "proxmox" — connection settings for the Proxmox API
# ---------------------------------------------------------------------------
# This tells the provider HOW to connect to your Proxmox cluster.
#
# AUTHENTICATION:
# We use an API token (not username/password) because:
#   1. Tokens can be scoped with limited permissions
#   2. Tokens don't expire like session tickets
#   3. Tokens can be revoked without changing user passwords
#
# The token format is: "user@realm!token-name=secret-uuid"
# Example:  terraform@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# SECURITY NOTE:
# Never hardcode tokens here! They come from variables, which you set in
# terraform.tfvars (git-ignored) or via environment variables:
#   export TF_VAR_proxmox_api_token="terraform@pam!terraform=..."
# ---------------------------------------------------------------------------
provider "proxmox" {
  # The Proxmox API endpoint — always use HTTPS
  endpoint = var.proxmox_api_url

  # API token authentication (preferred over username/password)
  api_token = var.proxmox_api_token

  # TLS verification — set to true if you have valid certs on Proxmox.
  # Set to false if using Proxmox's default self-signed certificate.
  insecure = var.proxmox_tls_insecure

  # SSH connection for operations that require it (e.g. file uploads).
  # The provider may need SSH access to the target Proxmox node to upload
  # cloud-init snippets or perform certain disk operations.
  ssh {
    agent = true # Use your local SSH agent for authentication
    username = "rasmus"
  }
}
