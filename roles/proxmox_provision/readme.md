# Proxmox Provision
A provisioning role to deploy VM's in proxmox from template.

## Requirements
See: requirements.yml
Note: this role uses template variables from the "proxmox" role in this repo

1. Requires ```{{ infadmin_password }}``` to be defined in your secrets.yml encyrpted vault

## Useage
All vars are optional depending on your configuration.
* If no ```vm_name``` is defined, a random 8-char string will be chosen as VM name
* All other VM configuration will use the template defaults unless otherwise specifed

```
    roles:
        - role: proxmox_provision
        vars:
            vm_name: my_vm                      # VM Name, otherwise random
            vm_memory: 10240                    # Memory MB to assign VM
            vm_cpu: 4                           # vCPU's to assign VM
            vm_network_bridge: vmbr1            # Proxmox bridge interface
            vm_network_vlan: 901                # VLAN
            vm_network_mac: 06:FF:DB:D0:60:B2   # MAC address to assign VM NIC
            vm_disk_increase: 46                # Increase template disk by #GB
            vm_pcie_device: "03:00.0"           # Include PCIe device

            vm_start: yes                       # Auto start the VM after provision
            vm_enable_agent: yes                # Enable the qemu agent
```

## Sources

Guide used to create this role: https://vectops.com/2020/01/provision-proxmox-vms-with-ansible-quick-and-easy/
Role uses module: https://docs.ansible.com/ansible/2.9/modules/proxmox_kvm_module.html
