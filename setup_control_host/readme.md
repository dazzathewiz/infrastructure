# Setup/add a control host
Generate a user SSH key (~/.ssh/id_ed25519_infadmin) and apply to all infrastructure hosts

## Requirements
1. Ansible installed - Use a machine that has Ansible installed (not Windows) and SSH

## Usage
```
ansible-playbook run.yml
```

## SSH Key
The key is stored in ```~/.ssh/{{keyfilename}}```
Change the keyfilename variable in ../group_vars/all/vars.yml
No passphrase is applied to the key, although you may add a passphase after creation: ```ssh-keygen -p -f ~/.ssh/{{group_vars/all/keyfilename}}```