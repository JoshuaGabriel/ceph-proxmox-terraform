

## Setup
Terraform cli installation
https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli

Copy of the template tfvars and fill out the proxmox information and number of VMs needed
```
cp terraform.tfvars.template terraform.tfvars
```

### Deployment

Common terraform commands

```
terraform plan 
```

```
terraform apply
```

```
terraform destroy
```

## Get all VM info with IPs
```
terraform output vm_info
```
## Get just the IPs
```
terraform output vm_ips
```
## Generate Ansible inventory

First playbook is ran to setup root user and enable ssh root login
```
terraform output -raw ansible_inventory > inventory.ini
ansible-playbook -i inventory.ini setup-root-ssh.yml
```

## Create another batch of VMs

change your vm_count inside terraform.tfvars:
```
# Change from 4 to 8
vm_count = 8
```

```
terraform plan   # Shows it will add 4 new VMs
terraform apply  # Creates jblanch-node-05, jblanch-node-06, jblanch-node-07, jblanch-node-08
```
You can also change the user_prefix to name the new VMs


setup ceph.pub key in hosts
```
ansible-playbook -i inventory.ini setup-ceph-ssh.yml
```

