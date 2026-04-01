# ============================================================================
# variables.tf — Input Variables
# ============================================================================
#
# WHAT ARE VARIABLES?
# Variables are the "knobs and dials" of your Terraform config. They let you
# reuse the same .tf files for different VMs, environments, or clusters
# without changing the code — just change the variable values.
#
# HOW ARE VARIABLES SET? (in order of precedence, lowest to highest)
#   1. Default value defined here (fallback)
#   2. terraform.tfvars file (the most common way)
#   3. Environment variables: export TF_VAR_variable_name="value"
#   4. Command line: terraform apply -var="vm_name=myvm"
#
# TYPES:
#   string  — text value
#   number  — integer or float
#   bool    — true or false
#   list    — ordered collection  e.g. ["a", "b", "c"]
#   map     — key-value pairs     e.g. { key = "value" }
#   object  — structured type with named attributes
# ============================================================================


# ===========================================================================
# Proxmox Connection Variables
# ===========================================================================

variable "proxmox_api_url" {
  description = "URL of the Proxmox API (e.g. https://192.168.86.20:8006)"
  type        = string

  # Validation blocks enforce rules BEFORE Terraform tries to apply anything.
  # This catches typos and misconfigurations early, saving you time.
  validation {
    condition     = can(regex("^https://", var.proxmox_api_url))
    error_message = "The Proxmox API URL must start with https://."
  }
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the format 'user@realm!tokenname=secret'"
  type        = string
  sensitive   = true # Marks this variable as secret — Terraform will hide
                     # its value in plan/apply output and logs. Always use
                     # this for tokens, passwords, and other credentials.
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS certificate verification (true for self-signed certs)"
  type        = bool
  default     = true # Proxmox ships with self-signed certs by default
}


# ===========================================================================
# VM Identity & Placement Variables
# ===========================================================================

variable "vm_name" {
  description = "Hostname for the new VM (also used as the Proxmox VM name)"
  type        = string

  validation {
    # RFC 1123 hostname: lowercase alphanumeric and hyphens, max 63 chars
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.vm_name))
    error_message = "VM name must be a valid hostname (lowercase, alphanumeric/hyphens, 2-63 chars)."
  }
}

variable "vm_id" {
  description = "Proxmox VM ID (unique integer). Set to 0 for auto-assign."
  type        = number
  default     = 0 # 0 = let Proxmox pick the next available ID

  validation {
    condition     = var.vm_id >= 0 && var.vm_id <= 999999999
    error_message = "VM ID must be between 0 (auto) and 999999999."
  }
}

variable "vm_description" {
  description = "Optional description shown in the Proxmox UI for this VM"
  type        = string
  default     = "Managed by Terraform"
}

variable "target_node" {
  description = "Which Proxmox node to create the VM on"
  type        = string
  default     = "proxmox1" # Your primary node — override for proxmox2/proxmox3
}

variable "template_id" {
  description = "VM ID of the Fedora Cloud template to clone from"
  type        = number
  default     = 9000 # Matches the template creation instructions in README
}


# ===========================================================================
# VM Resource Variables
# ===========================================================================

variable "cpu_cores" {
  description = "Number of CPU cores to allocate"
  type        = number
  default     = 2

  validation {
    condition     = var.cpu_cores >= 1 && var.cpu_cores <= 16
    error_message = "CPU cores must be between 1 and 16."
  }
}

variable "cpu_type" {
  description = <<-EOT
    CPU type exposed to the VM. Options:
    - "x86-64-v2-AES" — good default, broad compatibility with modern features
    - "host"           — exposes all host CPU features (best performance, less portable)
    - "qemu64"         — maximum compatibility (useful for migration between different CPUs)
  EOT
  type        = string
  default     = "x86-64-v2-AES"
}

variable "memory_mb" {
  description = "RAM in megabytes"
  type        = number
  default     = 2048

  validation {
    condition     = var.memory_mb >= 512 && var.memory_mb <= 65536
    error_message = "Memory must be between 512 MB and 64 GB."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in gigabytes (will be expanded from the template's disk)"
  type        = number
  default     = 32

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 500
    error_message = "Disk size must be between 10 GB and 500 GB."
  }
}

variable "storage_pool" {
  description = "Proxmox storage pool for the VM disk"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "Proxmox datastore for cloud-init snippets. Using NAS avoids filling local disks."
  type        = string
  default     = "SanxerNas"
}


# ===========================================================================
# Network Variables
# ===========================================================================

variable "network_bridge" {
  description = "Proxmox network bridge to attach the VM to"
  type        = string
  default     = "vmbr0" # Adjust to match your bridge carrying tagged VLANs
}

variable "vlan_id" {
  description = <<-EOT
    VLAN tag for the VM's network interface.
    Your VLANs:
      86 = TrustedServerLAN (192.168.86.0/24)
      87 = IoTandGuest      (192.168.87.0/24)
    Set to -1 for no VLAN tag (native/untagged).
  EOT
  type        = number
  default     = 86

  validation {
    condition     = var.vlan_id == -1 || (var.vlan_id >= 1 && var.vlan_id <= 4094)
    error_message = "VLAN ID must be -1 (no tag) or between 1 and 4094."
  }
}

variable "ip_address" {
  description = "Static IPv4 address in CIDR notation (e.g. 192.168.86.100/24)"
  type        = string

  validation {
    condition     = can(cidrhost(var.ip_address, 0))
    error_message = "Must be a valid CIDR address (e.g. 192.168.86.100/24)."
  }
}

variable "gateway" {
  description = "Default gateway IPv4 address"
  type        = string
  default     = "192.168.86.1" # pfSense VLAN 86 gateway
}

variable "dns_servers" {
  description = "List of DNS server IPs (Pi-hole first, then fallback)"
  type        = list(string)
  default     = ["192.168.86.10"] # Your Pi-hole on HomeLab3
}


# ===========================================================================
# Cloud-Init / User Configuration Variables
# ===========================================================================

variable "ci_user" {
  description = "Default user account created by cloud-init"
  type        = string
  default     = "rasmus"
}

variable "ci_ssh_public_key" {
  description = <<-EOT
    SSH public key for the default user. Paste your full public key string.
    Example: "ssh-ed25519 AAAAC3Nz... rasmus@workstation"
    
    Tip: You can also set this via environment variable:
      export TF_VAR_ci_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
  EOT
  type        = string
}

variable "timezone" {
  description = "System timezone for the VM"
  type        = string
  default     = "Europe/Copenhagen"
}

variable "vm_tags" {
  description = <<-EOT
    Tags to apply to the VM in Proxmox. Useful for filtering and organisation.
    Example: ["terraform", "fedora", "production"]
  EOT
  type        = list(string)
  default     = ["terraform", "fedora"]
}
