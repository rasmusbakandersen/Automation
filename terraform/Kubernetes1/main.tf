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
