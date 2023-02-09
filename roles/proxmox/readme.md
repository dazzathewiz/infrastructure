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
  - Network in /etc/network/interfaces can be setup with ```--tags network```
  - NFS mount point can be set with ```--tags nfs```
2. Downloading of cloud images and ISO's to configured NFS ISO share ```ansible-playbook proxmox.yml --tags update_images```
3. Clusters together all proxmox nodes in the playbook ```ansible-playbook proxmox.yml --tags cluster```
4. Creation of VM template for use on each nodes local-* storage ```ansible-playbook proxmox.yml --tags templates --ask-vault-password```
5. Setup Metric Server to ship metrics to InfluxDB ```ansible-playbook proxmox.yml --tags metrics --ask-vault-password```
6. Setup and initalise Ceph ```ansible-playbook proxmox.yml --tags ceph --ask-vault-password```

### 1. Setup
- apt sources to point to non-enterprise (no subscription), and ensures apt packages are updated after changing sources
- sets "iommu=on" for either Intel or AMD based CPU's in Grub config
- sets the hostname of the proxmox host to be the same as configured in ansible hosts file
- sets DNS servers in /etc/resolv.conf as defined in global group_vars -> all.yml -> dns
- manages the network setup in /etc/network/interfaces, depending on config for ```pve_second_nic_regex``` and ```pve_ceph_enabled```
- attaches NFS storage defined in vars -> main.yml -> nfs (use: ```--tags nfs|mounts```)

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

### 5. Metrics Server
- adds metrics servers to proxmox (works with clusters). Proxmox uses Graphite or InfluxDB integrations. 
  These variables can be referenced for this role. Example using a v2 InfluxDB:
```
vars:
  pve_metrics_servers:
    - name: InfluxDB
      port: 8089
      server: 172.23.0.1
      type: influxdb
      bucket: proxmox
      influxdbproto: http
      organization: homelab
      token: "{{ your_token_var }}"
      # use when need to update an existing metric server token:
      #updatetoken: yes
```
All variables can be seen in [pve_metrics_server.yml][metrics-yaml], or lookup the [Proxmox API][proxmox-api-metrics]

Further reading can be found:
- [Proxmox External Metric Server][metrics-doc2]
- [Proxmox Admin Guide: Metric Server][metrics-doc1]
- [Youtube guide][metrics-guide]

### 6. Ceph
This will setup Ceph by performing:
- Package install and initalisation of ceph
- Mon and Mgr deployments on all nodes
- [Dashboard][ceph-dashboard] setup and configuration

Required to enable Ceph configuration:
```
vars:
  pve_ceph_enabled: yes
```


## Ceph Management
I don't automate all of Ceph configuration because this is a homelab environment and I prefer to do these tasks
manually due to situational dynamics and avoiding automation hazards that lead to data loss:
- OSD Setup and configuration
- Pool configuration
- CephFS (metadata)

### OSD Management
OSD commands I've used are captured in [OSD Create Script][osd-script], but this script is not used by Ansible automation
Consideration for OSD's:
- Encryption via ```--encrypted 1``` or ```--dmcrypt``` flags, for ```pve-ceph``` and ```ceph-volume``` respectively
- [Multiple OSD's for single NVME devices][osd-nvme]
- WAL/DB disk - I have chosen not to have separate WAL/DB in my environment at this time as I don't expect large writes to be an issue for write performance. I don't perfectly understand the DB metadata location and whether in my pool implementation where metadata is on NVME crush device class pools.

### Pools
I create Pools manually, managed using the Dashboard: ```https://{{ pve_ceph_net_front_base }}:8443/#/pool```
[ceph-pools]

### VM Storage Pool 
I want to use an Erasure Coded pool for Proxmox on NVME disk. Some manual steps are required to set this up in Proxmox, including creating a separate MetaData pool (Proxmox expects the MetaData pool to be a replicated pool, not EC)
Includes:
- Ceph_Prox_MetaDataREP: MetaData Pool for Proxmox VM's
[ceph-crush-1]
[ceph-pool-1]
- Ceph_NVME-EC3: The Erasure-Coded pool for Proxmox (k=2, m=1). Note that [EC Overwrites][ceph-erasure-ecoverwrite] are required for VM storage to work in Proxmox
[ceph-crush-2]
[ceph-pool-2]

Adding the Pool into Proxmox:
Browsing to Datacentre -> Storage -> add RBD -> Ceph_Prox_MetaDataREP; This will add the REP pool, but you need to configure VM "data" to be stored on the Erasure Coded pool.

Change the data-pool for the ceph replica pool in /etc/pve/storage.cfg:
```
rbd: ceph-vm
       content images,rootdir
       krbd 0
       pool Ceph_Prox_MetaDataREP
       data-pool Ceph_NVME_EC3
```

### CephFS Pools
Referring to [Proxmox CephFS documentation][ceph-fs] for the setup of Metadata Server (MDS)
1. Create a _metadata pool with a replica set (required for metadata)
- cephfs_plexdata_metadata: Holds the metadata for the CephFS system
[ceph-pool-3]
2. Create a _data pool with erasurecode as desired
- cephfs_plexdata_data: the Erasure Coded pool for CephFS
[ceph-crush-3]
[ceph-pool-4]
3. Set the ```--bulk``` flag on the _data pool: ```ceph osd pool set ceph_plexdata_data bulk true```; See: [ceph-tune][Ceph Tuning]
4. Go to node -> Ceph -> CephFS -> Create Meta Data servers x3 (for each host)
5. Create CephFS (note the ```--force``` required for the EC pool as the default data pool) 
- ```ceph fs new cephfs_plexdata cephfs_plexdata_metadata ceph_plexdata_data --force```
6. Change the MDS to have 2 active metadata servers, I think this is better fault tolerance from my research
- ```ceph fs set cephfs_plexdata max_mds 2```

7. (Optional) Can mount the filesystem: Datacentre -> Storage -> Add -> CephFS

### Managing ceph host reboots
To manage a ceph host reboot in a fault tolerant manner;
- Ensure the host is not running an active Metadata Server (MDS) ```ceph mds fail {{ host }}```
- Prevent the CRUSH rule from rebalancing when a host goes offline: ```ceph osd set-group noout {{ host }}```
When complete:
- Re-enable CRUSH reblancing for OSD's ```ceph osd unset-group noout {{ host }}```

See more information about [troubleshooting and maintenance of OSDs][ceph-ods-maintain]

### Removing/Destroying Ceph Pools
To Remove/Destroy Ceph pools
1. Unmount any of the RBD/CephFS from clients inlucuding proxmox (Datacentre -> Storage -> Remove)
2. For CephFS:
  a) stop (and destroy) all mds under proxmox node -> Ceph -> CephFS
  b) disable the CephFS filesystem ```ceph fs rm cephfs_plexdata --yes-i-really-mean-it```
3. Remove Ceph pools from proxmox (cannot be done from Ceph dashboard); Ceph -> Pools -> Destroy

Other undo steps:
1. Remove mgr's: ```pveceph mgr destroy localhost|prox2|prox3``` - run on individual host
2. Uninstall "ceph-mgr-dashboard" on all hosts ```apt remove ceph-mgr-dashboard```
3. Delete Mons under node -> ceph -> monitor
4. ```pveceph purge```
5. ```rm /etc/ceph/ceph.conf /etc/pve/ceph.conf```
6. Cleanup the OSD disks. Note that ceph holds the OSD information in /var/lib/...etc. This is purged
 and as a result OSD cannot be "re-imported". They need to be destroyed:
  a) remove LVM volumes in node -> Disks -> LVM -> disk -> more -> Destroy


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
[metrics-doc1]: https://pve.proxmox.com/pve-docs/pve-admin-guide.html#external_metric_server
[metrics-doc2]: https://pve.proxmox.com/wiki/External_Metric_Server
[metrics-guide]: https://www.youtube.com/watch?v=f2eyVfCTLi0
[proxmox-api-metrics]: https://pve.proxmox.com/pve-docs/api-viewer/#/cluster/metrics/server/{id}
[metrics-yaml]: https://github.com/dazzathewiz/infrastructure/blob/994457c505061ee0aae937d260deac0e005878ee/roles/proxmox/tasks/pve_metrics_server.yml
[ceph-dashboard]: https://docs.ceph.com/en/quincy/mgr/dashboard/#:~:text=The%20Ceph%20Dashboard%20is%20a,a%20Ceph%20Manager%20Daemon%20module.
[osd-script]: files/create_osds.sh
[osd-nvme]: https://forum.proxmox.com/threads/recommended-way-of-creating-multiple-osds-per-nvme-disk.52252/
[ceph-erasure-ecoverwrite]: https://docs.ceph.com/en/latest/rados/operations/erasure-code/#erasure-coding-with-overwrites
[ceph-fs]: https://pve.proxmox.com/wiki/Deploy_Hyper-Converged_Ceph_Cluster#pveceph_fs
[ceph-tune]: https://ceph.io/en/news/blog/2022/autoscaler_tuning/
[ceph-osd-maintain]: https://docs.ceph.com/en/quincy/rados/troubleshooting/troubleshooting-osd/
[ceph-pools]: files/ceph_pools.png
[ceph-crush-1]: files/crush_rule_1.png
[ceph-pool-1]: files/ceph_pools.png
[ceph-crush-2]: files/crush_rule_2.png
[ceph-pool-2]: files/pool_2.png
[ceph-pool-3]: files/pool_3.png
[ceph-crush-3]: files/crush_rule_3.png
[ceph-pool-4]: files/pool_4.png
