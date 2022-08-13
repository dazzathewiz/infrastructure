# Infrastructure
An attempt to manage Infrastructure as Code in my homelab/environment

## Requirements
1. Ansible installed - Use a machine that has Ansible installed (WSL if on Windows) and SSH
2. Install required Ansible roles: ```ansible-galaxy install -r requirements.yml```

## Managing Secrets (passwords)
Check-out this repository on your local machine and setup a secrets file with your passwords;
```
cd group_vars
ansible-vault create secret.yml
```
secret.yml should contain:
```
infadmin_password: "***password***"
nut_upsd_password: "***password***"
```

To edit the secret.yml later:
```
ansible-vault edit secret.yml
```

## Usage
See sections below for:
- Setup local machine as an Infrastructure Control Host
- Provision MaaS on Hyper-V with Vagrant
- Proxmox configuration management
- DietPi configuration management

## Setup local machine as an Infrastructure Control Host
```
ansible-playbook setup-control-host.yml
```
This will create an SSH key ~/.ssh/id_ed25519_infadmin and configure hosts in your ~/.ssh/config

No passphrase is applied to the key, although you may add a passphase after creation: ```ssh-keygen -p -f ~/.ssh/id_ed25519_infadmin```

The playbook will also attempt to copy the public key to all hosts. You likely will need to specify the admin password if the machine
ansible doesn't already have pub keys on the ansible hosts. ```ansible-playbook setup-control-host.yml -k```

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

## Dietpi Configuration Management
Ensure you have group_vars/secret.yml setup with variables for the environment. The dietpi's use the 'common' role to reset the password of 'dietpi' user to that specified in group_vars/secret.yml -> infadmin_password

### Configure a dietpi
Note:
1. Your dietpi will need to have finished its 'first run' setup. You can ssh dietpi and ssh will tell you if setup is still running.
2. You need to handle the vault-password in your environment. You can choose to specify the vault password manually by appending ```--ask-vault-password``` 
3. On first run the dietpi password and ssh keys have not been provisioned. Append ```-k``` to ask for root password of your dietpi

Base bootstrap: ```ansible-playbook dietpi-default.yml -k --ask-vault-password```

pi-ups (manages UPS stats in the homelab): ```ansible-playbook pi-ups.yml -k --ask-vault-password```
