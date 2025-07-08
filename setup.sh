#!/bin/bash

set -ex

#terraform apply -auto-approve
terraform output -raw ansible_inventory > inventory.ini
ansible-playbook -i inventory.ini setup-root-ssh.yml
ansible-playbook -i inventory.ini setup-ceph-ssh.yml
ansible-playbook -i inventory.ini setup-cephadm.yml
ansible-playbook -i inventory.ini setup-docker-registry.yml -e "insecure_registry=10.0.0.225:5000"
ansible-playbook -i inventory.ini bootstrap-cluster.yml
