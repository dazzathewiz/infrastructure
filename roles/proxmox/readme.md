# Proxmox

A simple role to baseline configuration of Proxmox in infrastructure

## Requirements

None

## Example Playbook

See proxmox.yml

```yaml
---
- hosts: proxmox
  roles:
    - proxmox
```

## Functionality

The playbook sets up:
- apt sources to point to non-enterprise (no subscription), and ensures apt packages are updated after changing sources
- sets "iommu=on" for either Intel or AMD based CPU's in Grub config
- ensures vmbr0 (nic) is "VLAN aware" - sets `bridge-vlan-aware yes` in nic interfaces file
- sets DNS servers in /etc/resolv.conf as defined in global group_vars -> all.yml -> dns
- attaches NFS storage defined in vars -> main.yml -> nfs
- ensures the latest ISO versions are available on the NFS share, which are defined in vars -> main.yml -> images
