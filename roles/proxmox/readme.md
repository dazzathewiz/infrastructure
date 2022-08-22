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
    - proxmox/setup
```

## Functionality

The playbook sets up:
- apt sources to point to non-enterprise (no subscription), and ensures apt packages are updated after changing sources
- sets "iommu=on" for either Intel or AMD based CPU's in Grub config
- sets the hostname of the proxmox host to be the same as configured in ansible hosts file
- ensures vmbr0 (nic) is "VLAN aware" - sets `bridge-vlan-aware yes` in nic interfaces file
- sets DNS servers in /etc/resolv.conf as defined in global group_vars -> all.yml -> dns
- attaches NFS storage defined in vars -> main.yml -> nfs
- ensures the latest ISO versions are available on the NFS share, which are defined in vars -> main.yml -> images

## Clustering

The clustering functions are derived from https://github.com/lae/ansible-role-proxmox
See defaults for variables, refer to lae.proxmox for more information:
```
pve_cluster_clustername: "TEST"
pve_cluster_enabled: yes
pve_cluster_ha_groups: []
```
You can also configure [HA manager groups][ha-group]


[ha-group]: https://pve.proxmox.com/wiki/High_Availability#ha_manager_groups