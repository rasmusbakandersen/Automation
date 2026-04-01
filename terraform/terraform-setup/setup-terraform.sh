#!/bin/bash
# Run this on HomeLab1 as rasmus
# Usage: bash setup-terraform.sh

set -euo pipefail

BASE="/home/rasmus/automation/terraform"
mkdir -p "$BASE/cloud-init"
cd "$BASE"

echo "Creating Terraform project in $BASE ..."

# ============================================================================
# providers.tf
# ============================================================================
cat > providers.tf << 'ENDOFFILE'
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
  }
}
ENDOFFILE

# ============================================================================
# variables.tf
# ============================================================================
cat > variables.tf << 'ENDOFFILE'
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
ENDOFFILE

# ============================================================================
# main.tf
# ============================================================================
cat > main.tf << 'ENDOFFILE'
# ============================================================================
# main.tf — VM Resource Definition
# ============================================================================
#
# This is the core of your Terraform config. It defines:
#   1. A cloud-init user-data file (uploaded to Proxmox as a snippet)
#   2. The virtual machine itself (cloned from your Fedora Cloud template)
#
# KEY TERRAFORM CONCEPTS USED HERE:
#   resource  — declares something Terraform should create and manage
#   locals    — computed values reused within the config (like local variables)
#   file()    — reads a file from disk at plan time
#   templatefile() — reads a file and substitutes variables into it
#   depends_on — explicitly declares ordering between resources
# ============================================================================


# ---------------------------------------------------------------------------
# Local Values
# ---------------------------------------------------------------------------
# `locals` lets you define computed values that you reference elsewhere.
# Think of them as intermediate variables — they keep your resource blocks
# clean and avoid repeating logic.
# ---------------------------------------------------------------------------
locals {
  # Determine the VLAN tag to apply. -1 means "no tag" (native/untagged).
  # We use this in the network_device block below.
  use_vlan = var.vlan_id != -1

  # Build the DNS nameserver string from the list variable.
  # Cloud-init expects a space-separated string for nameservers.
  dns_string = join(" ", var.dns_servers)
}


# ---------------------------------------------------------------------------
# Cloud-Init User-Data Snippet
# ---------------------------------------------------------------------------
# Cloud-init is the industry-standard tool for initialising cloud VMs.
# When a VM boots for the first time, cloud-init reads configuration from
# a "user-data" file and applies it: creates users, writes files, runs
# commands, installs packages, etc.
#
# Proxmox supports cloud-init natively. We upload our user-data as a
# "snippet" (a small text file stored on a Proxmox datastore), then
# reference it when creating the VM.
#
# The `proxmox_virtual_environment_file` resource uploads a file to Proxmox.
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  # `content_type` tells Proxmox what kind of file this is.
  # "snippets" is for small config files like cloud-init user-data.
  content_type = "snippets"

  # Which Proxmox datastore to store the snippet on.
  # Using the NAS so snippets are shared across all nodes and don't
  # consume local disk space. Requires "snippets" content type enabled:
  #   pvesm set SanxerNas --content images,iso,snippets
  datastore_id = var.snippet_storage

  # Which Proxmox node to upload to — must match where the VM will run.
  node_name = var.target_node

  # `source_raw` lets us provide file content directly (as opposed to
  # uploading from a local file path). We use `templatefile()` to inject
  # Terraform variables into the cloud-init YAML template.
  source_raw {
    # templatefile() reads cloud-init/fedora-cis.yaml and replaces
    # placeholders like ${ci_user} with actual variable values.
    data = templatefile("${path.module}/cloud-init/fedora-cis.yaml", {
      hostname   = var.vm_name
      ci_user    = var.ci_user
      ssh_key    = var.ci_ssh_public_key
      timezone   = var.timezone
      dns_servers = var.dns_servers
    })

    # The filename on Proxmox. We include the VM name so multiple VMs
    # don't overwrite each other's snippets.
    file_name = "${var.vm_name}-cloud-init.yaml"
  }
}


# ---------------------------------------------------------------------------
# Virtual Machine
# ---------------------------------------------------------------------------
# This is the main event — the `proxmox_virtual_environment_vm` resource
# creates (or updates) a virtual machine on Proxmox.
#
# We CLONE from the Fedora Cloud template rather than installing from ISO.
# Cloning is fast (seconds vs. minutes) and gives you a known-good base
# image every time.
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "vm" {
  # --- Identity -----------------------------------------------------------

  # Which Proxmox node to run on
  node_name = var.target_node

  # Human-readable name (shown in Proxmox UI and set as hostname)
  name = var.vm_name

  # Numeric VM ID. 0 = auto-assign the next available ID.
  vm_id = var.vm_id > 0 ? var.vm_id : null

  # Description shown in the Proxmox UI notes panel
  description = var.vm_description

  # Tags for organisation — visible in the Proxmox UI and API.
  # Useful for filtering: "show me all VMs tagged 'terraform'"
  tags = var.vm_tags


  # --- Clone from Template ------------------------------------------------
  # Instead of installing from scratch, we clone the Fedora Cloud template.
  # Proxmox creates a linked or full copy of the template's disk.
  # ---------------------------------------------------------------------------
  clone {
    vm_id = var.template_id # ID of the template VM (9000 from our setup)
    full  = true            # Full clone = independent disk copy.
                            # Linked clones are faster but depend on the
                            # template disk — if the template is deleted,
                            # linked clones break. Full is safer.
  }


  # --- CPU ----------------------------------------------------------------
  cpu {
    cores = var.cpu_cores
    type  = var.cpu_type

    # NUMA (Non-Uniform Memory Access) — improves performance on multi-socket
    # hosts by associating CPU cores with nearby memory. Safe to enable even
    # on single-socket systems (it just has no effect).
    numa = true
  }


  # --- Memory -------------------------------------------------------------
  memory {
    dedicated = var.memory_mb # Fixed RAM allocation (no ballooning)

    # Ballooning dynamically adjusts RAM — the hypervisor can reclaim unused
    # memory from this VM and give it to others. We disable it for
    # predictable performance (CIS recommendation: know your resource usage).
    # Set floating = var.memory_mb to explicitly disable ballooning.
    floating = var.memory_mb
  }


  # --- Boot Disk ----------------------------------------------------------
  # The disk block configures the cloned disk. Even though we're cloning,
  # we can resize the disk here (cloud-init + growpart will expand the
  # filesystem at first boot).
  # ---------------------------------------------------------------------------
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"    # Must match the template's disk interface
    size         = var.disk_size_gb
    iothread     = true       # Dedicated I/O thread — reduces latency for
                              # disk operations by offloading them from the
                              # main QEMU thread. Recommended for virtio-scsi.
    discard      = "on"       # Enable TRIM/discard — allows the guest OS to
                              # inform the storage that blocks are no longer
                              # in use, reclaiming space on thin-provisioned
                              # storage (like local-lvm).
    ssd          = true       # Tell the guest this is an SSD. Enables the
                              # guest kernel to optimise I/O scheduling.
                              # Set to false if your Proxmox storage is on
                              # spinning disks.
  }


  # --- Network Interface --------------------------------------------------
  # Attaches a virtual NIC to the specified bridge and VLAN.
  # ---------------------------------------------------------------------------
  network_device {
    bridge = var.network_bridge
    model  = "virtio" # virtio is the paravirtualised NIC — much faster than
                      # emulated e1000. Always use virtio for Linux guests.

    # Conditionally apply the VLAN tag. When vlan_id is -1, we omit it
    # entirely (no tag = native VLAN on the bridge).
    vlan_id = local.use_vlan ? var.vlan_id : null
  }


  # --- Cloud-Init Configuration ------------------------------------------
  # The `initialization` block configures Proxmox's built-in cloud-init
  # support. This sets network config and points to our user-data snippet.
  # ---------------------------------------------------------------------------
  initialization {
    # Network configuration passed to cloud-init
    ip_config {
      ipv4 {
        address = var.ip_address # Static IP in CIDR notation
        gateway = var.gateway
      }
    }

    # DNS configuration
    dns {
      servers = var.dns_servers
      domain  = "sanxer.dk"
    }

    # Reference to our uploaded cloud-init user-data snippet.
    # This is the CIS-hardened config from cloud-init/fedora-cis.yaml.
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }


  # --- QEMU Guest Agent --------------------------------------------------
  # The guest agent runs inside the VM and communicates with Proxmox.
  # It enables: proper shutdown, filesystem freeze for backups, and
  # reporting the VM's IP address back to the Proxmox UI.
  # Install `qemu-guest-agent` in cloud-init (we do this in the YAML).
  # ---------------------------------------------------------------------------
  agent {
    enabled = true
  }


  # --- Serial Console -----------------------------------------------------
  # Required for cloud images that use serial console for output.
  # Also useful for accessing the VM via `qm terminal <vmid>` if
  # networking is broken.
  # ---------------------------------------------------------------------------
  serial_device {}


  # --- Operating System Type ----------------------------------------------
  operating_system {
    type = "l26" # Linux 2.6+ kernel (used for all modern Linux)
  }


  # --- Startup Behaviour --------------------------------------------------

  # Start the VM immediately after Terraform creates it
  started = true

  # Auto-start this VM when the Proxmox node boots
  on_boot = true


  # --- Lifecycle Rules ----------------------------------------------------
  # `lifecycle` controls how Terraform handles certain situations.
  #
  # `ignore_changes` tells Terraform to NOT revert changes made outside
  # of Terraform (e.g. manually in the Proxmox UI, or by Ansible).
  # Without this, Terraform would try to "fix" any drift every time
  # you run `terraform apply`.
  # ---------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [
      # If you manually resize the disk later, don't shrink it back
      disk[0].size,
      # If Ansible changes network config, don't revert it
      initialization,
    ]
  }
}


# ============================================================================
# BONUS: Multi-VM Example with for_each (commented out)
# ============================================================================
# Once you're comfortable with the single-VM setup above, you can provision
# multiple VMs at once using `for_each`. Uncomment and adapt as needed.
#
# `for_each` iterates over a map and creates one resource instance per entry.
# Each instance is independently managed — you can add/remove VMs from the
# map without affecting the others.
# ============================================================================

# variable "vms" {
#   description = "Map of VMs to create"
#   type = map(object({
#     target_node = optional(string, "proxmox1")
#     cpu_cores   = optional(number, 2)
#     memory_mb   = optional(number, 2048)
#     disk_size_gb = optional(number, 32)
#     vlan_id     = number
#     ip_address  = string
#   }))
#   default = {
#     "homelab6" = {
#       vlan_id    = 86
#       ip_address = "192.168.86.13/24"
#     }
#     "homelab7" = {
#       target_node = "proxmox2"
#       cpu_cores   = 4
#       memory_mb   = 4096
#       vlan_id     = 86
#       ip_address  = "192.168.86.14/24"
#     }
#     "iot-gateway" = {
#       vlan_id    = 87
#       ip_address = "192.168.87.10/24"
#     }
#   }
# }
#
# resource "proxmox_virtual_environment_vm" "multi" {
#   for_each  = var.vms
#   node_name = each.value.target_node
#   name      = each.key  # The map key becomes the VM name
#   # ... same blocks as above, using each.value.cpu_cores, etc.
# }
ENDOFFILE

# ============================================================================
# outputs.tf
# ============================================================================
cat > outputs.tf << 'ENDOFFILE'
# ============================================================================
# outputs.tf — Output Values
# ============================================================================
#
# WHAT ARE OUTPUTS?
# Outputs are values that Terraform prints after `terraform apply` completes.
# They're useful for:
#   1. Seeing key info at a glance (IP address, VM ID, etc.)
#   2. Passing values to other Terraform modules or external scripts
#   3. Querying later with `terraform output vm_ip_address`
#
# Outputs are also what makes Terraform modules composable — a module's
# outputs become another module's inputs.
# ============================================================================

output "vm_id" {
  description = "Proxmox VM ID assigned to the new VM"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_name" {
  description = "Name/hostname of the VM"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "vm_node" {
  description = "Proxmox node the VM is running on"
  value       = proxmox_virtual_environment_vm.vm.node_name
}

output "vm_ip_address" {
  description = "Static IP address assigned to the VM"
  value       = var.ip_address
}

output "ssh_command" {
  description = "Quick SSH command to connect to the new VM"
  value       = "ssh ${var.ci_user}@${split("/", var.ip_address)[0]}"
}

output "vm_tags" {
  description = "Tags applied to the VM"
  value       = proxmox_virtual_environment_vm.vm.tags
}
ENDOFFILE

# ============================================================================
# terraform.tfvars.example
# ============================================================================
cat > terraform.tfvars.example << 'ENDOFFILE'
# ============================================================================
# terraform.tfvars.example — Example Variable Values
# ============================================================================
#
# HOW TO USE:
#   1. Copy this file:  cp terraform.tfvars.example terraform.tfvars
#   2. Fill in your actual values
#   3. NEVER commit terraform.tfvars to Git (it contains secrets!)
#      Add it to .gitignore:  echo "terraform.tfvars" >> .gitignore
#
# Terraform automatically loads terraform.tfvars when you run plan/apply.
# You can also use multiple .tfvars files:
#   terraform apply -var-file="production.tfvars"
# ============================================================================


# --- Proxmox Connection ---------------------------------------------------

proxmox_api_url    = "https://192.168.86.22:8006" # proxmox3
proxmox_api_token  = "terraform@pam!terraform=YOUR-SECRET-TOKEN-UUID-HERE"
proxmox_tls_insecure = true # Set false if you install real TLS certs


# --- VM Identity ----------------------------------------------------------

vm_name        = "test-vm"
vm_id          = 0          # 0 = auto-assign
vm_description = "Test VM provisioned by Terraform"
target_node    = "proxmox3" # Where your template (9000) lives
template_id    = 9000       # Fedora Cloud template ID


# --- VM Resources ---------------------------------------------------------

cpu_cores   = 2
cpu_type    = "x86-64-v2-AES"
memory_mb   = 2048
disk_size_gb = 32
storage_pool = "local-lvm"
snippet_storage = "SanxerNas" # NAS-backed storage for cloud-init snippets


# --- Network --------------------------------------------------------------

network_bridge = "vmbr0"
vlan_id        = 86                 # 86 = TrustedServerLAN, 87 = IoTandGuest, -1 = no tag
ip_address     = "192.168.86.100/24"
gateway        = "192.168.86.1"     # pfSense gateway for VLAN 86
dns_servers    = ["192.168.86.10"]  # Pi-hole on HomeLab3


# --- Cloud-Init / User ---------------------------------------------------

ci_user           = "rasmus"
ci_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... rasmus@workstation"
timezone          = "Europe/Copenhagen"
vm_tags           = ["terraform", "fedora"]
ENDOFFILE

# ============================================================================
# .gitignore
# ============================================================================
cat > .gitignore << 'ENDOFFILE'
# ============================================================================
# .gitignore — Keep secrets and generated files out of Git
# ============================================================================

# Terraform state files contain the full state of your infrastructure,
# including any sensitive values (API tokens, IPs, etc.).
# For a homelab, local state is fine. For teams, use remote state (S3, etc.)
*.tfstate
*.tfstate.*

# Crash logs from Terraform itself
crash.log
crash.*.log

# The .terraform directory contains downloaded provider plugins and modules.
# It's regenerated by `terraform init` — no need to commit it.
.terraform/
.terraform.lock.hcl

# CRITICAL: terraform.tfvars contains your API token and other secrets.
# NEVER commit this to Git.
terraform.tfvars
*.auto.tfvars

# OS junk
.DS_Store
Thumbs.db

# Editor swap files
*.swp
*.swo
*~
ENDOFFILE

# ============================================================================
# cloud-init/fedora-cis.yaml
# ============================================================================
# NOTE: This file uses ${variable} syntax for Terraform templatefile().
# The 'ENDOFFILE' heredoc is NOT single-quoted here so we can write
# the dollar-brace syntax literally — but we need to escape any bash
# variables. Since there are no bash variables in this content, it's safe.
# ============================================================================
cat > cloud-init/fedora-cis.yaml << 'ENDOFFILE'
#cloud-config
# ============================================================================
# Fedora Cloud-Init — CIS-Aligned Baseline Hardening
# ============================================================================
#
# This cloud-init config runs ONCE on first boot and applies:
#   - User account creation with SSH key
#   - Package installation (guest agent, security tools)
#   - CIS Level 1 kernel and filesystem hardening
#   - Network stack hardening (sysctl)
#   - SSH server hardening (password auth left ENABLED for now)
#   - Audit framework basics
#   - Firewalld enabled with default deny
#
# IMPORTANT: This is provisioning-level hardening only. Further
# configuration (disabling password SSH, CrowdSec, Wazuh agent, etc.)
# is handled by Ansible post-provisioning.
#
# Variables like ${hostname} are replaced by Terraform's templatefile().
# ============================================================================


# ---------------------------------------------------------------------------
# Hostname
# ---------------------------------------------------------------------------
hostname: ${hostname}
manage_etc_hosts: true
# Sets /etc/hostname and updates /etc/hosts so the VM knows its own name.


# ---------------------------------------------------------------------------
# User Account
# ---------------------------------------------------------------------------
# CIS 5.4.1 recommends strong user/group management.
# We create a single admin user with sudo and SSH key access.
# The default "fedora" user from the cloud image is removed.
# ---------------------------------------------------------------------------
users:
  - name: ${ci_user}
    groups: wheel           # wheel = sudo group on Fedora/RHEL
    sudo: ALL=(ALL) NOPASSWD:ALL  # Passwordless sudo (lock down later with Ansible)
    shell: /bin/bash
    lock_passwd: false      # Allow password login (will be hardened by Ansible)
    ssh_authorized_keys:
      - ${ssh_key}

# Remove the default "fedora" cloud user if it exists
runcmd_early:
  - userdel -r fedora 2>/dev/null || true


# ---------------------------------------------------------------------------
# Timezone & Locale
# ---------------------------------------------------------------------------
timezone: ${timezone}


# ---------------------------------------------------------------------------
# Package Installation
# ---------------------------------------------------------------------------
# Install essential packages before applying hardening.
# qemu-guest-agent: communicates with Proxmox for graceful shutdown & IP reporting
# audit/aide:       CIS requirement for system auditing and file integrity
# firewalld:        CIS requirement for host-based firewall
# chrony:           CIS requirement for time synchronisation (NTP)
# ---------------------------------------------------------------------------
package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - audit
  - audit-libs
  - aide
  - firewalld
  - chrony
  - policycoreutils-python-utils  # SELinux management tools
  - tmux
  - curl
  - vim-enhanced


# ---------------------------------------------------------------------------
# CIS Hardening: Filesystem & Kernel Modules
# ---------------------------------------------------------------------------
# CIS 1.1.1.x — Disable mounting of uncommon filesystem types.
# These are rarely needed on servers and reduce the attack surface.
# We blacklist them via modprobe so the kernel can't load them.
# ---------------------------------------------------------------------------
write_files:

  # --- CIS 1.1.1: Disable unused filesystems ---
  - path: /etc/modprobe.d/cis-filesystems.conf
    owner: root:root
    permissions: "0644"
    content: |
      # CIS 1.1.1.1 — Disable cramfs (compressed ROM filesystem)
      install cramfs /bin/true
      blacklist cramfs

      # CIS 1.1.1.2 — Disable freevxfs (Veritas filesystem)
      install freevxfs /bin/true
      blacklist freevxfs

      # CIS 1.1.1.3 — Disable jffs2 (flash filesystem)
      install jffs2 /bin/true
      blacklist jffs2

      # CIS 1.1.1.4 — Disable hfs (macOS Classic filesystem)
      install hfs /bin/true
      blacklist hfs

      # CIS 1.1.1.5 — Disable hfsplus (macOS Extended filesystem)
      install hfsplus /bin/true
      blacklist hfsplus

      # CIS 1.1.1.6 — Disable squashfs (compressed read-only filesystem)
      # NOTE: Remove this line if you use snap packages
      install squashfs /bin/true
      blacklist squashfs

      # CIS 1.1.1.7 — Disable udf (Universal Disk Format, used by DVDs)
      install udf /bin/true
      blacklist udf

  # --- CIS 1.1.1.8 — Disable USB storage (optional, uncommon on servers) ---
  - path: /etc/modprobe.d/cis-usb-storage.conf
    owner: root:root
    permissions: "0644"
    content: |
      install usb-storage /bin/true
      blacklist usb-storage


  # -------------------------------------------------------------------------
  # CIS 1.5.1 — Restrict core dumps
  # -------------------------------------------------------------------------
  # Core dumps can contain sensitive data (passwords, keys in memory).
  # Disabling them prevents accidental information disclosure.
  # -------------------------------------------------------------------------
  - path: /etc/security/limits.d/cis-core-dumps.conf
    owner: root:root
    permissions: "0644"
    content: |
      # CIS 1.5.1 — Disable core dumps for all users
      *    hard    core    0

  - path: /etc/sysctl.d/50-cis-coredump.conf
    owner: root:root
    permissions: "0644"
    content: |
      # CIS 1.5.1 — Disable SUID core dumps
      fs.suid_dumpable = 0


  # -------------------------------------------------------------------------
  # CIS 3.x — Network Stack Hardening (sysctl)
  # -------------------------------------------------------------------------
  # These kernel parameters harden the TCP/IP stack against common attacks:
  # spoofing, redirect-based MITM, SYN floods, and information leaks.
  # -------------------------------------------------------------------------
  - path: /etc/sysctl.d/60-cis-network.conf
    owner: root:root
    permissions: "0644"
    content: |
      # --- CIS 3.1.1 — Disable IP forwarding ---
      # Servers should not route packets between interfaces.
      # Enable ONLY if this VM is a router/firewall.
      net.ipv4.ip_forward = 0
      net.ipv6.conf.all.forwarding = 0

      # --- CIS 3.2.1 — Disable source-routed packets ---
      # Source routing lets senders specify the route. Attackers abuse this
      # to bypass firewalls. No legitimate use on modern networks.
      net.ipv4.conf.all.accept_source_route = 0
      net.ipv4.conf.default.accept_source_route = 0
      net.ipv6.conf.all.accept_source_route = 0
      net.ipv6.conf.default.accept_source_route = 0

      # --- CIS 3.2.2 — Disable ICMP redirect acceptance ---
      # ICMP redirects can be used for MITM attacks by telling your server
      # to route traffic through an attacker-controlled gateway.
      net.ipv4.conf.all.accept_redirects = 0
      net.ipv4.conf.default.accept_redirects = 0
      net.ipv6.conf.all.accept_redirects = 0
      net.ipv6.conf.default.accept_redirects = 0

      # --- CIS 3.2.3 — Disable secure ICMP redirect acceptance ---
      # Even "secure" redirects from known gateways should be ignored.
      net.ipv4.conf.all.secure_redirects = 0
      net.ipv4.conf.default.secure_redirects = 0

      # --- CIS 3.2.4 — Log suspicious (martian) packets ---
      # Martian packets have impossible source addresses. Logging them
      # helps detect spoofing attempts and misconfigured networks.
      net.ipv4.conf.all.log_martians = 1
      net.ipv4.conf.default.log_martians = 1

      # --- CIS 3.2.5 — Ignore broadcast ICMP requests ---
      # Prevents the server from participating in Smurf amplification attacks.
      net.ipv4.icmp_echo_ignore_broadcasts = 1

      # --- CIS 3.2.6 — Ignore bogus ICMP error responses ---
      net.ipv4.icmp_ignore_bogus_error_responses = 1

      # --- CIS 3.2.7 — Enable Reverse Path Filtering ---
      # Drops packets where the source address doesn't match the interface
      # they arrived on. Strong anti-spoofing measure.
      net.ipv4.conf.all.rp_filter = 1
      net.ipv4.conf.default.rp_filter = 1

      # --- CIS 3.2.8 — Enable TCP SYN Cookies ---
      # Protects against SYN flood DoS attacks by using cryptographic
      # cookies instead of allocating resources for half-open connections.
      net.ipv4.tcp_syncookies = 1

      # --- CIS 3.2.9 — Disable IPv6 router advertisements ---
      # Servers should not accept router advertisements (SLAAC).
      # Your network uses static IPs via DHCP/cloud-init anyway.
      net.ipv6.conf.all.accept_ra = 0
      net.ipv6.conf.default.accept_ra = 0

      # --- Additional hardening ---
      # ASLR (Address Space Layout Randomization) — randomises memory
      # layout to make exploitation harder. Level 2 = full randomisation.
      kernel.randomize_va_space = 2

      # Restrict access to kernel logs (prevents info leaks)
      kernel.dmesg_restrict = 1

      # Restrict kernel pointer exposure in /proc
      kernel.kptr_restrict = 2

      # Disable sending ICMP redirects (we're not a router)
      net.ipv4.conf.all.send_redirects = 0
      net.ipv4.conf.default.send_redirects = 0


  # -------------------------------------------------------------------------
  # CIS 5.2 — SSH Server Hardening
  # -------------------------------------------------------------------------
  # NOTE: PasswordAuthentication is left YES per your request.
  # Ansible will disable it later after deploying key-only auth.
  #
  # All other settings follow CIS Level 1 recommendations.
  # -------------------------------------------------------------------------
  - path: /etc/ssh/sshd_config.d/50-cis-hardening.conf
    owner: root:root
    permissions: "0600"
    content: |
      # ---- CIS 5.2 SSH Server Hardening ----

      # CIS 5.2.4 — Limit authentication attempts per connection
      MaxAuthTries 4

      # CIS 5.2.5 — Require idle timeout (seconds inactive before disconnect)
      ClientAliveInterval 300
      ClientAliveCountMax 3

      # CIS 5.2.6 — Disable .rhosts authentication (legacy, insecure)
      IgnoreRhosts yes

      # CIS 5.2.7 — Disable host-based authentication
      HostbasedAuthentication no

      # CIS 5.2.8 — Disable root login via SSH
      PermitRootLogin no

      # CIS 5.2.9 — Disable empty passwords
      PermitEmptyPasswords no

      # CIS 5.2.10 — Disable X11 forwarding (unnecessary on servers)
      X11Forwarding no

      # CIS 5.2.11 — Set login grace time (seconds to complete auth)
      LoginGraceTime 60

      # CIS 5.2.13 — Restrict SSH to strong ciphers
      Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

      # CIS 5.2.14 — Restrict SSH to strong MACs
      MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

      # CIS 5.2.15 — Restrict SSH to strong key exchange algorithms
      KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

      # CIS 5.2.20 — Limit concurrent unauthenticated connections
      MaxStartups 10:30:60

      # CIS 5.2.21 — Set SSH banner
      Banner /etc/issue.net

      # ---- DELIBERATELY KEPT ENABLED (will be hardened by Ansible) ----
      # PasswordAuthentication yes  (sshd default is yes, so no line needed)


  # -------------------------------------------------------------------------
  # Login warning banner (CIS 1.7)
  # -------------------------------------------------------------------------
  - path: /etc/issue.net
    owner: root:root
    permissions: "0644"
    content: |
      ******************************************************************
      *  This system is privately owned. Unauthorised access is        *
      *  prohibited. All connections may be monitored and recorded.    *
      ******************************************************************

  - path: /etc/issue
    owner: root:root
    permissions: "0644"
    content: |
      ******************************************************************
      *  This system is privately owned. Unauthorised access is        *
      *  prohibited. All connections may be monitored and recorded.    *
      ******************************************************************


  # -------------------------------------------------------------------------
  # CIS 4.1.1.x — Audit daemon configuration
  # -------------------------------------------------------------------------
  # Basic audit rules to log security-relevant events. Ansible can
  # deploy a more comprehensive ruleset later.
  # -------------------------------------------------------------------------
  - path: /etc/audit/rules.d/cis-baseline.rules
    owner: root:root
    permissions: "0640"
    content: |
      # CIS 4.1.4 — Log changes to user/group identity files
      -w /etc/group -p wa -k identity
      -w /etc/passwd -p wa -k identity
      -w /etc/gshadow -p wa -k identity
      -w /etc/shadow -p wa -k identity
      -w /etc/security/opasswd -p wa -k identity

      # CIS 4.1.6 — Log changes to network configuration
      -w /etc/sysconfig/network -p wa -k system-network
      -w /etc/hosts -p wa -k system-network

      # CIS 4.1.7 — Log changes to system administration scope (sudoers)
      -w /etc/sudoers -p wa -k scope
      -w /etc/sudoers.d/ -p wa -k scope

      # CIS 4.1.8 — Log login and logout events
      -w /var/log/lastlog -p wa -k logins
      -w /var/run/faillock -p wa -k logins

      # CIS 4.1.15 — Log changes to date and time
      -a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
      -a always,exit -F arch=b64 -S clock_settime -k time-change
      -w /etc/localtime -p wa -k time-change

      # CIS 4.1.17 — Make audit config immutable (requires reboot to change)
      # Uncomment this AFTER you're happy with your rules:
      # -e 2


  # -------------------------------------------------------------------------
  # Default umask hardening (CIS 5.4.4)
  # -------------------------------------------------------------------------
  - path: /etc/profile.d/cis-umask.sh
    owner: root:root
    permissions: "0644"
    content: |
      # CIS 5.4.4 — Set default umask to 027
      # This means new files are readable only by owner and group,
      # not by "others". More restrictive than the default 022.
      umask 027


# ---------------------------------------------------------------------------
# Run Commands (executed in order on first boot)
# ---------------------------------------------------------------------------
runcmd:
  # ---- Apply sysctl settings immediately ----
  - sysctl --system

  # ---- Enable and start essential services ----
  # qemu-guest-agent: Proxmox integration
  - systemctl enable --now qemu-guest-agent

  # firewalld: host-based firewall (CIS 3.5)
  # Default zone is "public" which denies all inbound except SSH.
  - systemctl enable --now firewalld

  # auditd: system auditing (CIS 4.1)
  - systemctl enable --now auditd

  # chronyd: NTP time sync (CIS 2.2.1)
  - systemctl enable --now chronyd

  # ---- CIS 1.3.1 — Initialise AIDE (file integrity monitoring) ----
  # AIDE creates a database of file checksums. Later, you can run
  # `aide --check` to detect unauthorized file changes.
  # This takes a minute or two on first run.
  - aide --init
  - mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

  # ---- CIS 6.1 — Fix critical file permissions ----
  - chmod 644 /etc/passwd
  - chmod 644 /etc/group
  - chmod 000 /etc/shadow
  - chmod 000 /etc/gshadow
  - chown root:root /etc/passwd /etc/group /etc/shadow /etc/gshadow

  # ---- Clean up: remove the default fedora user if it exists ----
  - userdel -r fedora 2>/dev/null || true

  # ---- SELinux: ensure enforcing mode (CIS 1.6) ----
  # Fedora Cloud images ship with SELinux enabled. Verify it's enforcing.
  - sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  - setenforce 1 || true


# ---------------------------------------------------------------------------
# Final reboot
# ---------------------------------------------------------------------------
# Reboot after cloud-init completes to ensure all kernel parameters,
# module blacklists, and service configurations take full effect.
# ---------------------------------------------------------------------------
power_state:
  mode: reboot
  message: "Cloud-init hardening complete — rebooting"
  timeout: 30
  condition: true
ENDOFFILE

# ============================================================================
# Done!
# ============================================================================
echo ""
echo "Project created at $BASE"
echo ""
echo "Files:"
find "$BASE" -type f | sort | sed "s|$BASE/||"
echo ""
echo "Next steps:"
echo "  cd $BASE"
echo "  cp terraform.tfvars.example terraform.tfvars"
echo "  vim terraform.tfvars    # Fill in your API token, SSH key, IP"
echo "  terraform init"
echo "  terraform plan"
