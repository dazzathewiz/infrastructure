# Infrastructure
An attempt to manage Infrastructure as Code in my homelab/environment

## Requirements
1. Ansible installed - Use a machine that has Ansible installed (WSL if on Windows) and SSH

## Usage
See sections below for:
- Setup local machine as an Infrastructure Control Host
- Provision MaaS on Hyper-V with Vagrant

## Setup local machine as an Infrastructure Control Host
```
ansible-playbook setup-control-host.yml
```
This will create an SSH key ~/.ssh/id_ed25519_infadmin and configure hosts in your ~/.ssh/config

No passphrase is applied to the key, although you may add a passphase after creation: ```ssh-keygen -p -f ~/.ssh/id_ed25519_infadmin```