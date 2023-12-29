# System role
A role for managing the system base

## Requirements
See: requirements.yml

## Useage
By default the role manages:
* Update installed packages and reboot the system
* Set the timezone
* Enable system powersaving when host is in a `host_group` called `'baremetal'` (IE: for physical systems)

Addtionally the role will manage:
* Add package repositories
* Installation of packages not yet installed and automatically reboot if required
* Partitioning of disk drives
* Mount points when specified are mounted and put into system fstab

## Example
```
  roles:
    - role: system
      vars:
        packages:                               # List of packages to be installed
          - nfs-common
          - open-iscsi
        manage_packages: yes                    # Automatically manage packages for installtion or add package repositories
        upgrade_packages: yes                   # Upgrade packages already installed
        add_apt_repository:                     # List extra repositories to be added
          - "ppa:nfs-ganesha/nfs-ganesha-4"
        auto_reboot: yes                        # Allow the system to reboot after upgrades or package install (only reboots if required)
        set_timezone: yes                       # Set the timezone specified by {{ timezone }}
        partition_devices:                      # Partition the named device as described or with defaults (further below)
          - /dev/nvme0n1
          - device: /dev/sdb
            mount: /mnt/special                 # Mount this device on /mnt/special
        fstype: ext4                            # Default parition type
        auto_mount: yes                         # Automatically mount paritioned drives
        default_mountpoint: /mnt                # Default mount path when auto-mounting paritioned drives
        mounts:                                 # List of disks to mount to volume
          - { src: /dev/sdb1, fstype: auto }                    # Simple mount of disk /dev/sdb1 to /mnt/sdb
          - { path: /mnt/disk1, src: UUID=6d1faaa6-3179-4218-b936-7639a2832b67, fstype: xfs }               # mount by UUID xfs drive to /mnt/disk1
          - { path: /mnt/disk2, src: UUID=7cd7a54a-94ed-416d-89e9-fc12ea42d6c0, fstype: ext4 }              # mount by UUID ext4 drive to /mnt/disk1
          - { path: /mnt/nas/data src: "192.168.0.1:/mnt/pool/data", fstype: nfs, opts: 'auto,nofail,noatime,nolock,intr,tcp,actimeo=1800' }    # NFS mount from NAS
          - { path: /mnt/storage, src: /mnt/disk*, fstype: fuse.mergerfs, opts: 'allow_other,direct_io,use_ino,category.create=mfs,moveonenospc=true,minfreespace=2G,fsname=myfs' }    # MergerFS mount
```
