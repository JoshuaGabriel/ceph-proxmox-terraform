# main.tf
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc01"
    }
  }
}

provider "proxmox" {
  pm_api_url          = "https://10.0.0.19:8006/api2/json"
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
  pm_parallel = 4
}

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

variable "proxmox_template" {
  description = "Name of template in proxmox to copy"
  type        = string 
}


variable "user_prefix" {
  description = "User prefix for VM names and identification (e.g., 'alice', 'bob')"
  type        = string
  default     = "user"
}

variable "vm_configs" {
  description = "VM configuration profiles"
  type = map(object({
    cores  = number
    memory = number
    disks = list(object({
      size    = string
      storage = string
      type    = string
    }))
  }))
  default = {
    standard = {
      cores  = 2
      memory = 2048
      disks = [
        {
          size    = "50G"
          storage = "local-lvm"
          type    = "system"
        }
      ]
    }
    waldb = {
      cores  = 4
      memory = 8192
      disks = [
        {
          size    = "50G"
          storage = "local-lvm"
          type    = "system"
        },
        {
          size    = "500G"
          storage = "local-lvm"
          type    = "data"
        },
        {
          size    = "500G"
          storage = "local-lvm"
          type    = "data"
        },
        {
          size    = "500G"
          storage = "local-ssd"
          type    = "data"
        }
      ]
    }
    normal = {
      cores  = 4
      memory = 8192
      disks = [
        {
          size    = "50G"
          storage = "local-lvm"
          type    = "system"
        },
        {
          size    = "500G"
          storage = "local-lvm"
          type    = "data"
        },
        {
          size    = "500G"
          storage = "local-lvm"
          type    = "data"
        },
        {
          size    = "500G"
          storage = "local-lvm"
          type    = "data"
        }
      ]
    }
  }
}

variable "vm_profile" {
  description = "VM profile to use (standard, waldb, normal)"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "waldb", "normal"], var.vm_profile)
    error_message = "VM profile must be one of: standard, waldb, normal."
  }
}

locals {
  vm_names = [for i in range(var.vm_count) : "${var.user_prefix}-node-${format("%02d", i + 1)}"]
  selected_config = var.vm_configs[var.vm_profile]
}

resource "proxmox_vm_qemu" "cluster_nodes" {
  count = var.vm_count
  
  name        = local.vm_names[count.index]
  target_node = "pve"
  clone       = var.proxmox_template
  
  cpu {
    cores   = local.selected_config.cores
    sockets = 1
  }
  memory = local.selected_config.memory
  
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }
  
  os_type = "cloud-init"
  sshkeys = var.ssh_public_key
  ciuser = "debby"
  ipconfig0 = "ip=dhcp"
  agent = 1
  
  disks {
    scsi {
      scsi0 {
        disk {
          size    = "32G"
          storage = "local-lvm"
        }
      }
      
      dynamic "scsi1" {
        for_each = length(local.selected_config.disks) > 1 ? [local.selected_config.disks[1]] : []
        content {
          disk {
            size    = scsi1.value.size
            storage = scsi1.value.storage
          }
        }
      }
      
      dynamic "scsi2" {
        for_each = length(local.selected_config.disks) > 2 ? [local.selected_config.disks[2]] : []
        content {
          disk {
            size    = scsi2.value.size
            storage = scsi2.value.storage
          }
        }
      }
      
      dynamic "scsi3" {
        for_each = length(local.selected_config.disks) > 3 ? [local.selected_config.disks[3]] : []
        content {
          disk {
            size    = scsi3.value.size
            storage = scsi3.value.storage
          }
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
  
  boot = "order=scsi0"
  scsihw = "virtio-scsi-single"
  bios = "ovmf"
  automatic_reboot = false
  
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}

output "vm_info" {
  value = {
    for i, vm in proxmox_vm_qemu.cluster_nodes : local.vm_names[i] => {
      vm_id      = vm.vmid
      name       = vm.name
      ip_address = vm.default_ipv4_address
    }
  }
}

output "ansible_inventory" {
  value = join("\n", concat([
    "[cluster_nodes]"
  ], [
    for i, vm in proxmox_vm_qemu.cluster_nodes : 
    "${local.vm_names[i]} ansible_host=${vm.default_ipv4_address}"
  ]))
}

output "vm_ips" {
  value = [for vm in proxmox_vm_qemu.cluster_nodes : vm.default_ipv4_address]
}
