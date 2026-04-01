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
