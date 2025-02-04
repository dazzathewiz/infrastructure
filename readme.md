# Infrastructure
An attempt to manage Infrastructure as Code in my homelab/environment

## Requirements
1. Ansible installed - Use a machine that has Ansible installed (WSL if on Windows) and SSH
2. Install required Ansible roles: ```ansible-galaxy install -r requirements.yml```

## Managing Secrets (passwords)
Check-out this repository on your local machine and setup a secrets file with your passwords;
```
cd group_vars
ansible-vault create secret.yml
```
secret.yml should contain:
```
infadmin_password: "***password***"
nut_upsd_password: "***password***"
```

To edit the secret.yml later:
```
ansible-vault edit secret.yml
```

### 1Password
For some plays, the host requires [1Password CLI][opcli] to access secrets. Ensure your host has this installed:
1. `brew install 1password-cli`

## Usage
See sections below for:
- Setup local machine as an Infrastructure Control Host
- Provision MaaS on Hyper-V with Vagrant
- Proxmox configuration management
- DietPi configuration management

## Setup local machine as an Infrastructure Control Host
```
ansible-playbook setup-control-host.yml
```
This will create an SSH key ~/.ssh/id_ed25519_infadmin and configure hosts in your ~/.ssh/config

No passphrase is applied to the key, although you may add a passphase after creation: ```ssh-keygen -p -f ~/.ssh/id_ed25519_infadmin```

The playbook will also attempt to copy the public key to all hosts. You likely will need to specify the admin password if the machine
ansible doesn't already have pub keys on the ansible hosts. ```ansible-playbook setup-control-host.yml -k```

## Proxmox Configuration Management
```
ansible-playbook proxmox.yml --ask-vault-password
```

### Requirements
1. Proxmox hosts defined under 'proxmox' group in hosts file.
2. SSH keys setup with the Infrastructure Control Host role above -> ```ansible-playbook setup-control-host.yml -k```
3. A Proxmox host with basic installation from ISO completed
    a) If not clustering multiple hosts, change ```pve_cluster_enabled: no``` variable in you playbook.
    b) If you are clustering, install from ISO by selecting ZFS - this will allow local storage replication to other nodes
4. DNS servers defined in group_vars/all.yml

### Ceph Management
Refer to: [Proxmox Readme][proxmox-readme]

*** NOTE: Modify `proxmox-reboot.yml` and run `ansible-playbook proxmox-reboot.yml` for handling Ceph failovers/tolerance

## Dietpi Configuration Management
Ensure you have group_vars/secret.yml setup with variables for the environment. The dietpi's use the 'common' role to reset the password of 'dietpi' user to that specified in group_vars/secret.yml -> infadmin_password

### Configure a dietpi
Note:
1. Your dietpi will need to have finished its 'first run' setup. You can ssh dietpi and ssh will tell you if setup is still running.
2. You need to handle the vault-password in your environment. You can choose to specify the vault password manually by appending ```--ask-vault-password``` 
3. On first run the dietpi password and ssh keys have not been provisioned. Append ```-k``` to ask for root password of your dietpi

Base bootstrap: ```ansible-playbook dietpi-default.yml -k --ask-vault-password```

pi-ups (manages UPS stats in the homelab): ```ansible-playbook pi-ups.yml -k --ask-vault-password```
pifour: ```ansible-playbook pifour.yml -k --ask-vault-password```

## Kubernetes cluster with k3s

To setup k3s infrastructure, use [dazzathewiz/ks3-ansible][k3s-ansible]

### Deploy k3s nodes on proxmox
Requirements:
1. Ensure proxmox nodes are configured in `hosts`
    ```
    [k3s_master]
    <masters>               -> Cluster etc/master nodes
    [k3s_node]
    <nodes>                 -> Cluster workload nodes
    [k3s_longhorn_storage]
    <storage_nodes>         -> These nodes expect to have a /dev/nvme0 device for Longhorn storage
    ```
2. Define the work node settings in `host_vars/<nodename>.yml` 
    Note:
    - `lspci` to identify devices to pass through, then specify in host_vars for each host `k3s_worker_pcie:`
    - Passthough disks to k3s worker nodes using their `ls /dev/disk/by-id` name for `k3s_worker_disk_passthrough`

    Example:
    ```
    k3s_worker_pcie:
    - "02:00.0"       # 1TB Samsung 970 EVO NVMe - Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983
    - id: "00:02.0"   # Intel Corporation CometLake-S GT2 [UHD Graphics 630]
        mdev: "i915-GVTg_V5_4"

    k3s_worker_node_storage: 'local-nvme'

    k3s_worker_pcie:
      - "02:00.0"   # Typically NVME storage
      - "00:02.0"   # Typically the built in Intel UHD Graphics

    k3s_worker_virtual_disk:
      - '{{ vm_storage_default }}:931.53,format=raw'

    k3s_worker_disk_passthrough:
      - ata-ST4000VN000-1H4168_Z301GA45
      - ata-ST4000VN000-1H4168_Z3054AS0

    k3s_worker_node_memory: 36864
    k3s_worker_node_cpu: 6
    ```

Deploy the k3s nodes:
```ansible-playbook vm_deploy_kubernetes.yml --ask-vault-password```
Add the new nodes to the `hosts` file, then finalise basic configuration:
```ansible-playbook k3s.yml```

HA can be setup in proxmox for the k3smaster nodes who reside on shared storage:
1. Datacenter -> HA -> Groups
![Proxmox HA Groups](images/HA%20Groups.png)
2. With the k3smaster# node selected, go to More -> HA and configure with the desired group

### First time setup
1. ```git clone https://github.com/dazzathewiz/k3s-ansible```
2. ```cd k3s-ansible/inventory/<env>/group_vars```
3. Create ansible vault ```ansible-vault create inventory/prod/group_vars/secret.yml``` containing:
    - k3s_token                 -> k3s node token
    - github_token              -> github token to maintain fluxcd repo
    - onepassword_credentials   -> 1password-credentials.json file contents (See: [Secrets Automation Workflow][opautomation])
    - onepassword_vaulttoken_k3s -> Secrets Automation integration access token

### Run k3s cluster setup
1. ```ansible-playbook ./site.yml -i ./inventory/prod/hosts.ini -K -e @inventory/prod/group_vars/secret.yml --ask-vault-password```
2. Copy .kube config to local machine ```scp -i ~/.ssh/id_ed25519_infadmin infadmin@10.10.1.187:~/.kube/config ~/.kube/config```

### Note:
- Modify paths if the environemtn is different to "prod"
- ```-K``` required where your server is not configured for passwordless sudo
- ```-e @inventory/prod/group_vars/secret.yml``` required to specify the secretes vars file not set in the playbook.yml file
- Servers specified in the ```inventory/<env>/hosts.ini``` should be deployed and running with ssh keys deployed

## Bootstrap QEMU VM
```ansible <host or host_group> -m include_role -a name=vmguest -K```

## Storecrypt
```ansible-playbook storecrypt.yml --ask-vault-password```
```--tags``` Include: 
- provision
- 45drives
- config
- setup
- zfs
- containers*

* Note that ZFS doesn't install automatically; It was much easier to use Houston to configure ZFS 
import on storecrypt; see: https://miner.dazzathewiz.com:9090/

### Manual post-install activities for storecrypt
1. Deploy manually w/ Portainer and docker-compose: https://github.com/dazzathewiz/chia-forks.git
2. Fix telegraf hddtemp by running `sudo dpkg-reconfigure hddtemp` (see: https://github.com/dazzathewiz/infrastructure/issues/9)

## PiFour
```ansible-playbook pifour.yml --ask-vault-password```
```--tags``` Indclude:
- setup
- containers

## Chiamain
1. Ensure you have [1password-cli](#1Password) working
2. `ansible-playbook chiamain.yaml --ask-vault-password`
3. Start the docker stack with `docker-compose up -d` from home dir `~/`
4. SSL keys may need to be copied over from backup, if you expect existing harvesters to connect to master node

* Note it will take some time to do a DB copy if this is a first-time setup. DB sync can be painful and likely needs to be managed separately.

### Notes:
1. For new Shinobi deployments, setup the users and consider copying existing cameras via [Export/Import][shinobi-monitor]

[k3s-ansible]: https://github.com/dazzathewiz/k3s-ansible
[shinobi-monitor]: https://hub.shinobi.video/articles/view/QzWPj4vp8Y2k1R5
[proxmox-readme]: roles/proxmox/readme.md
[opautomation]: https://developer.1password.com/docs/connect/get-started/#step-1-set-up-a-secrets-automation-workflow
[opcli]: https://sculley.github.io/posts/2022/12/31/using-1password-to-automatically-retrieve-your-ansible-become-password.html
