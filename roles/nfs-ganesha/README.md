# NFS Ganesha

Largely followed Kubernetes@Home [dcplaya/homeops](https://github.com/dcplaya/home-ops), this implements a combinations of steps from [NFS-Ganesha Client Setup][nfs-ganesha-client-setup] and [45Drives NFS config][nfs-ganesha-45drives]

## Quick commands
Perform these commands on a NFS-Ganesha configured node:
 * `ganesha-rados-grace -p nfs-ganesha -n ganesha-namespace` - Get status of grace sync.
    For understanding FLAGS returned, see [ganesha-rados-grace](https://github.com/nfs-ganesha/nfs-ganesha/blob/V3-stable/src/doc/man/ganesha-rados-grace.rst)
    ```
    cur=6 rec=5
    ======================================================
    nfs-ganesha1	NE
    nfs-ganesha2	NE
    nfs-ganesha3	NE
    ```
 * `cat /var/log/ganesha/ganesha.log` - Ganesha logs
 * `cat /etc/ganesha/exports.cong` - Will show the export configuration. Note that exports are kept in Rados though and can be retrieved with next command
 * `rados -p nfs-ganesha -N ganesha-namespace get conf-shared /etc/ganesha/exports.conf` - Will get the Rados config `conf-shared`; Note this observes values of 
    - `pve_ceph_rados_nfs_pool: nfs-ganesha`
    - `pve_ceph_rados_nfs_pool_ganesha_namespace: ganesha-namespace`
    - `nfs_ganesha_rados_export: conf-shared`

## Ganesha Config
`ganesha.conf`; see [ganesha-config](https://github.com/nfs-ganesha/nfs-ganesha/blob/V3-stable/src/doc/man/ganesha-config.rst#id6)

## NFS Ganesha
Instructions have been largely adapted from [NFS-Ganesha Client Setup][nfs-ganesha-client-setup], but also looking up [45Drives Configuration][nfs-ganesha-45drives].

These are slightly different approaches and I have kept template files for both for prosterity:
  * [45drives.ganesha.conf.j2](templates/45drives.ganesha.conf.j2) is adapted from [45Drives Configuration][nfs-ganesha-45drives]
  * [rados.export.conf.j2](templates/rados.exports.conf.j2) is a manual way of creating exports, particularly for Proxmox which cannot leverage Cephadm orchestration
  * [local.ganesha.conf.j2](templates/local.ganesha.conf.j2) is the config file kept on disk of the NFS-Ganesha server at {{ pve_nfs_ganesha_conf }} - Step 3 of [NFS-Ganesha Client Setup][nfs-ganesha-client-setup]
  * [rados.ganesha.confg.j2](templates/rados.ganesha.conf.j2) is the config file kept in the rados storage for access by all NFS-Ganesha servers in the cluster - Step 1 of [NFS-Ganesha Client Setup][nfs-ganesha-client-setup]
  * [default.ganesha.conf](files/default.ganesha.conf) is the default configuration that came after fresh install of nfs-ganesha server

Note the 45drives version, which stores exports inside rados and allows configuration of NFS exports in the Ceph Dashboard, requires Cephadm to be enabled. The dashboard throws an error with Cephadm, which can't be configured to work with PVE. 
[45Drive NFS config][nfs-ganesha-45drives] gives details on their setup steps.

If you use Cephadm, manually enable the Ceph Dashboard with `ceph dashboard set-ganesha-clusters-rados-pool-namespace nfs-ganesha/ganesha-namespace`

## References
[Deploying an Active/Active NFS Cluster over CephFS](https://jtlayton.wordpress.com/2018/12/10/deploying-an-active-active-nfs-cluster-over-cephfs/)

[nfs-ganesha-45drives]: http://images.45drives.com/ceph/cephfs/nfs-ganesha-ceph.conf
[nfs-ganesha-client-setup]: https://github.com/dcplaya/home-ops/blob/main/k8s/clusters/cluster-1/manifests/rook-ceph-external/cluster/nfs-ganesha.md
