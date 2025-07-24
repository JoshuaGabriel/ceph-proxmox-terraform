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

variable "disk_count" {
  description = "Number of data disks to create (excluding system disk)"
  type        = number
  default     = 3
}

variable "disk_size" {
  description = "Size of each data disk (e.g., '500G', '1T')"
  type        = string
  default     = "500G"
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
    disk_storage = string
    disk_emulatessd = bool
    # For waldb profile, the last disk can use different storage
    last_disk_storage = optional(string)
    last_disk_emulatessd = optional(bool)
  }))
  default = {
    standard = {
      cores  = 2
      memory = 2048
      disk_storage = "local-lvm"
      disk_emulatessd = true
    }
    waldb = {
      cores  = 4
      memory = 8192
      disk_storage = "local-lvm"
      disk_emulatessd = false
      last_disk_storage = "local-ssd"
      last_disk_emulatessd = true
    }
    normal = {
      cores  = 4
      memory = 8192
      disk_storage = "local-lvm"
      disk_emulatessd = true
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
      
      dynamic "scsi" {
        for_each = range(1, var.disk_count + 1)
        content {
          disk {
            size    = var.disk_size
            storage = scsi.value == var.disk_count && local.selected_config.last_disk_storage != null ? local.selected_config.last_disk_storage : local.selected_config.disk_storage
            emulatessd = scsi.value == var.disk_count && local.selected_config.last_disk_emulatessd != null ? local.selected_config.last_disk_emulatessd : local.selected_config.disk_emulatessd
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
