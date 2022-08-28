# Proxmox

A simple role to baseline configuration of Proxmox in infrastructure

## Requirements

1. Hosts defined in the hosts file under group 'proxmox'. Hostnames must end with a number [0-9] EG: prox1, prox2, etc
2. ```dns: [0.0.0.0]``` variable list configured
3. NFS host setup with ISO share (for downloading ISO's) Configured in: vars/main.yml ```nfs:```

## Example Playbook

See ../proxmox.yml

```yaml
---
- hosts: proxmox
  roles:
    - proxmox
```

## Functionality

The playbook performs all of these by default (or independantly with tags):
1. Setup of a proxmox host ```ansible-playbook proxmox.yml --tags setup```
2. Downloading of cloud images and ISO's to configured NFS ISO share ```ansible-playbook proxmox.yml --tags update_images```
3. Clusters together all proxmox nodes in the playbook ```ansible-playbook proxmox.yml --tags cluster```
4. Creation of VM template for use on each nodes local-* storage ```ansible-playbook proxmox.yml --tags templates --ask-vault-password```

### 1. Setup
- apt sources to point to non-enterprise (no subscription), and ensures apt packages are updated after changing sources
- sets "iommu=on" for either Intel or AMD based CPU's in Grub config
- sets the hostname of the proxmox host to be the same as configured in ansible hosts file
- ensures vmbr0 (nic) is "VLAN aware" - sets `bridge-vlan-aware yes` in nic interfaces file
- sets DNS servers in /etc/resolv.conf as defined in global group_vars -> all.yml -> dns
- attaches NFS storage defined in vars -> main.yml -> nfs

### 2. Download of cloud images
- ensures the latest ISO versions are available on the NFS share, which are defined in vars -> main.yml -> images

### 3. Clustering
- adds all hosts into a cluster by default. To disable clustering, configure: ```pve_cluster_enabled: no```
** See the notes on clustering below **

### 4. VM Cloud image template
- creates a Ubuntu cloud image template with VM ID 800# where # is the host node number. 
  Template uses the following variables to be defined outside of this role:
     ```infadmin_password:``` to be set (in vault)
     ```provisioning_user:``` which will be the default user account in the cloudimage template configuration
     ```search_domain:```     default DNS search domain for cloud image VM's deployed


## Clustering

The clustering functions are derived from https://github.com/lae/ansible-role-proxmox
See defaults for variables, refer to lae.proxmox for more information:
```
pve_cluster_clustername: "TEST"
pve_cluster_enabled: yes
pve_cluster_ha_groups: []
```
You can also configure [HA manager groups][ha-group]

### A note on clustering:
If creating a 2 node cluster (less than 3 nodes), this works fine however when 1 node is down you won't be able to log into
the other node due to quorum configuration. If only 1 node in the cluster is online, ssh to the node and run command:
```pvecm expected 1```

[ha-group]: https://pve.proxmox.com/wiki/High_Availability#ha_manager_groups