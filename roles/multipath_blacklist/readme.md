# multipath_blacklist role
Blacklists `sd*` devices from `multipathd` on the k3s nodes so it can't claim Longhorn volumes.

## Why
Longhorn attaches each volume to its node as an iSCSI disk (`/dev/sdX`). If `multipathd` is running without a
blacklist it claims those disks, Longhorn can't mount them, and pods sit in `ContainerCreating` with mount errors such as:
```
MountVolume.SetUp failed for volume "pvc-..." : ... already mounted or mount point busy
```
The Ubuntu cloud image ships `multipath-tools` with `multipathd` enabled, so every new node is exposed until the blacklist is in place.

Reference: Longhorn KB [Troubleshooting: `MountVolume.SetUp failed for volume` due to multipathd on the node](https://longhorn.io/kb/troubleshooting-volume-with-multipath/)

## What it does
* Adds this managed block to `/etc/multipath.conf` (the rest of the file is left alone):
    ```
    # BEGIN ANSIBLE MANAGED BLOCK
    blacklist {
      devnode "^sd[a-z0-9]+"
    }
    # END ANSIBLE MANAGED BLOCK
    ```
* Restarts `multipathd` through a handler, only when the block was added or changed.
* If a node already has the same stanza written by hand (no markers), it is converted in place to the managed block.
  The effective config doesn't change, so `multipathd` is not restarted.
* Skips nodes without `multipath-tools` installed: there is no `multipathd` to claim the disks. It does not install the package.

The block and marker match the ones written by `k3s_server_post` in [k3s-ansible][k3s-ansible] on the masters,
so both playbooks agree and neither reports a change.

The blacklist covers every `sd*` device. That is fine while no node uses multipath legitimately (SAN/FC);
check `multipath -ll` before adding a node that does.

## Usage
Applied to `k3s_cluster` (masters and workers) by `k3s.yml`, which runs before the k3s-ansible `site.yml`,
so a new node has the blacklist before k3s and Longhorn use it:
```
ansible-playbook k3s.yml --tags multipath --check --diff
ansible-playbook k3s.yml --tags multipath
```
A `multipathd` restart on a node with attached volumes is low risk with the `sd` blacklist in place, but schedule it.

[k3s-ansible]: https://github.com/dazzathewiz/k3s-ansible
