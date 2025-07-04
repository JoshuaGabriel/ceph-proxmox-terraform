# main.tf
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc01"
    }
  }
}

# Configure the Proxmox Provider
provider "proxmox" {
  pm_api_url          = "https://10.0.0.19:8006/api2/json"
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
}

# Variables for sensitive data
variable "pm_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!token-name)"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  sensitive   = true
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 4
}

variable "user_prefix" {
  description = "User prefix for VM names and identification (e.g., 'alice', 'bob')"
  type        = string
  default     = "user"
}

# VM hostnames
locals {
  vm_names = [for i in range(var.vm_count) : "${var.user_prefix}-node-${format("%02d", i + 1)}"]
}

# Create VMs
resource "proxmox_vm_qemu" "cluster_nodes" {
  count = var.vm_count
  
  # Basic VM settings
  name        = local.vm_names[count.index]
  target_node = "pve"
  clone       = "ceph-test"
  
  # VM specifications
  cpu {
    cores   = 2
    sockets = 1
  }
  memory = 2048  # 2GiB in MB
  
  # Network configuration
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }
  
  # Cloud-init configuration
  os_type = "cloud-init"
  
  # SSH key injection
  sshkeys = var.ssh_public_key
  
  # Cloud-init user
  ciuser = "debian"
  
  # Use DHCP for automatic IP assignment
  ipconfig0 = "ip=dhcp"
  
  # Enable QEMU guest agent to get IP addresses
  agent = 1
  
  # Disk configuration with cloud-init
  disks {
    scsi {
      scsi0 {
        disk {
          size    = "100G"  # Match your template size
          storage = "local-lvm"
        }
      }
      scsi1 {
        disk {
          size    = "50G"
          storage = "local-lvm"
        }
      }
    }
    ide {
      ide3 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
  
  # Boot settings - match template configuration
  boot = "order=scsi0"
  scsihw = "virtio-scsi-single"
  bios = "ovmf"
  
  # Start VM after creation
  automatic_reboot = false
  
  # Wait for cloud-init to complete
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}

# Outputs
output "vm_info" {
  value = {
    for i, vm in proxmox_vm_qemu.cluster_nodes : local.vm_names[i] => {
      vm_id      = vm.vmid
      name       = vm.name
      ip_address = vm.default_ipv4_address
    }
  }
}

# Generate Ansible inventory with DHCP-assigned IPs
output "ansible_inventory" {
  value = join("\n", concat([
    "[cluster_nodes]"
  ], [
    for i, vm in proxmox_vm_qemu.cluster_nodes : 
    "${local.vm_names[i]} ansible_host=${vm.default_ipv4_address} ansible_user=debian"
  ]))
}

# Output just the IPs for easy copying
output "vm_ips" {
  value = [for vm in proxmox_vm_qemu.cluster_nodes : vm.default_ipv4_address]
}
