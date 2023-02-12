#!/bin/bash

# Example of OSD's created manually

# Prox1
pveceph osd create --encrypted 1 /dev/sdb
pveceph osd create --encrypted 1 /dev/sdc
ceph-volume lvm batch --osds-per-device 4 --crush-device-class nvme --dmcrypt /dev/nvme1n1

# Prox2
pveceph osd create --encrypted 1 /dev/sda
pveceph osd create --encrypted 1 /dev/sdc
ceph-volume lvm batch --osds-per-device 4 --crush-device-class nvme --dmcrypt /dev/nvme1n1

# Prox3
pveceph osd create --encrypted 1 /dev/sde
pveceph osd create --encrypted 1 /dev/sdf
ceph-volume lvm batch --osds-per-device 4 --crush-device-class nvme --dmcrypt /dev/nvme1n1

# Other

# Check OSDs (EG: determine if encrypted)
ceph-volume lvm list

#  stderr: [errno 13] RADOS permission denied (error connecting to the cluster)
# -->  RuntimeError: Unable to create a new OSD id
#   https://forum.proxmox.com/threads/unable-to-create-ceph-osd.56501/
# Solution: ensure the /etc/pve/priv/ceph.client.bootstrap-osd.keyring contains the same information on all nodes
