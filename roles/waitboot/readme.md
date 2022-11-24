# waitboot role
This role is a simple "hack" to get around a situation where a VM is provisioned by a play
but not yet available and the play needs to wait until the VM is actually booted.

Example:
```
- hosts: localhost
  roles:
    - provision_vm
    - waitboot
    - configure_vm
```

Uses the ```wait_for``` module: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html

Idea pulled from: https://stackoverflow.com/questions/68795165/how-to-put-pause-between-ansible-roles
