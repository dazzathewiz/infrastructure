# Infrastructure
An attempt to manage Infrastructure as Code in my homelab/environment

## Requirements
1. Ansible installed - Use a machine that has Ansible installed (WSL if on Windows) and SSH

## Usage
See sections below for:
- Setup local machine as an Infrastructure Control Host
- Provision MaaS on Hyper-V with Vagrant
- Proxmox configuration management

## Setup local machine as an Infrastructure Control Host
```
ansible-playbook setup-control-host.yml
```
This will create an SSH key ~/.ssh/id_ed25519_infadmin and configure hosts in your ~/.ssh/config

No passphrase is applied to the key, although you may add a passphase after creation: ```ssh-keygen -p -f ~/.ssh/id_ed25519_infadmin```

## Proxmox Configuration Management
```
ansible-playbook proxmox.yml
```

### Requirements
1. SSH keys setup with the Infrastructure Control Host role above
2. A Proxmox host with basic installation from ISO completed
3. SSH key copied to the new instance:
``` ssh-copy-id -i ~/.ssh/id_ed25519_infadmin.pub root@<host-ip> ```
4. DNS servers defined in group_vars/all.yml