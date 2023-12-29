# Proxmox Provision
A provisioning role to deploy VM's and LXC containers in proxmox from template.

## Requirements
See: requirements.yml
Note: this role uses template variables from the "proxmox" role in this repo

1. Requires ```{{ infadmin_password }}``` to be defined in your secrets.yml encyrpted vault

## Useage
All vars are optional depending on your configuration.
* If no `instance_name` is defined, a random 8-char string will be chosen as VM/LXC name
* A VM will be created unless otherwise specified `provision_type:`. Valid options are `vm` or `lxc`
* All other VM/container configuration will use the template defaults unless otherwise specifed

### Example VM Deployment
```
    roles:
        - role: proxmox_provision
        vars:
            instance_name: my_vm                    # VM Name, otherwise random
            vm_memory: 10240                        # Memory MB to assign VM
            vm_memory_min: 6114                     # Sets the minimum memory assigned to VM ballon
            vm_cpu: 4                               # vCPU's to assign VM
            vm_cpu_params: "flags=+pdpe1gb\\;+aes"  # --cpu parameters for `qm set`, note the '+' and double escape '\\'
            vm_network_bridge: vmbr1                # Proxmox bridge interface
            vm_network_vlan: 901                    # VLAN
            vm_network_mac: 06:FF:DB:D0:60:B2       # MAC address to assign VM NIC
            vm_disk_increase: 46                    # Increase template disk by #GB
            vm_disk_ssdemulation: no                # Tick SSD Emulation in VM SCSI0
            vm_disk_discard: no                     # Tick Discard in VM SCSI0
            vm_disk_virtual:                        # List extra virtual disks to be created
                - 'local-zfs:10,format=raw'             # Format should be 'STORAGE_ID:SIZE_IN_GB<,options>'
            vm_pcie_device: ["03:00.0"]             # Include listed PCIe devices, alternatively:
            vm_pcie_device:                         # Specify options for PCIe devices: https://pve.proxmox.com/pve-docs/qm.1.html
                - id: "03:00.0"
                  mdev: "i915-GVTg_V5_4"
                  rombar: "0"                       # Disable rombar support tickbox
                  gpu_primary: yes                  # Enable Primary GPU (x-vga=1)
            vm_storage: "ceph-vm"                   # The target storage location

            vm_start: yes                           # Auto start the VM after provision
            vm_enable_agent: yes                    # Enable the qemu agent
            vm_guest_trim: no                       # Run guest-trim after a disk move or VM migration, requires vm_enable_agent set to `yes`
            vm_hotplug_devices: "network,disk,usb"  # Selectively enable hotplug features. Comma separated list
            vm_enable_numa: no                      # Enable NUMA
```

### Example LXC Deployment
See [provision_lxc.yaml](tasks/provision_lxc.yaml) for more
```
    roles:
        - role: proxmox_provision
        vars:
            provision_type: lxc                 # Required for containers, otherwise defaults to 'vm'
            instance_name: my_container              # Container Name, otherwise random
            lxc_ostemplate_name: <name>.tar.gz  # Must be a template available on the host
            lxc_storage: local-lvm              # PVE storage where the container will be stored/run from
            pve_lxc_ostemplate_storage: local   # PVE storage name where templates are stored
            pve_lxc_vmid: 100                   # PVE instance ID (VMID)
            pve_lxc_description: Ansible.       # LXC description
            lxc_root_password: foobar           # Root password inside container
            lxc_root_authorized_pubkey: xyz     # Public Key for ssh key access
            pve_onboot: yes                     # Start container on pve host boot
            lxc_net_interfaces:
                - id: net0                      # Identifier
                    name: eth0                  # Instance interface
                    ip4: dhcp                   # Can be IP or 'dhcp'
                    bridge: vmbr1               # Promox host bridge
                    netmask4: 24                # Subnet mask in CIDR. Required when specifying ip4 IP (not DHCP)
```

## Sources

Guide used to create this role: https://vectops.com/2020/01/provision-proxmox-vms-with-ansible-quick-and-easy/
Role uses module: https://docs.ansible.com/ansible/2.9/modules/proxmox_kvm_module.html
LXC creation adapted from [UdelaRInterior/ansible-role-proxmox-create-lxc](https://github.com/UdelaRInterior/ansible-role-proxmox-create-lxc)
