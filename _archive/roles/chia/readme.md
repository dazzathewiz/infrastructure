# Ansible Role: Chia

Prepares/creates docker-compose.yml in home folder of ansible user deploy Chia docker containers. The docker-compose file will contain all required
 yaml settings for [Machinaris][machinaris-git] fullnodes and farmers.

## How to use

To use this role, variable configuration for the following should exist:
1. [Roles](#1-specify-roles)
2. [Blockchains and options](#2-specify-blockchainsalt-chains-and-options)
3. [Mnemonics](#3-handling-mnemonics)
4. [Data location](#4-container-data-path)
5. [Machinaris Controller IP](#5-machinaris-controller-ip)

Additionally some options are likley useful:
1. [Harvester plot directories](#1-harvester-plots)
2. [Docker Container Networks](#2-dockercontainer-network-configuration)
3. [Backup of container settings and blockchain DB](#3-backup-of-container-configuration-and-database)

  ### 1. Specify Roles

  Machinaris support multiple chia roles, however this Ansible role only supports:
  - fullnode (IE: blockchain db + farmer + harvester) = `chia_farmer`
  - harvester (Harvester only) = `chia_harvester`

  Ansible hosts specify the role they take by their `host_group`. Ansible hosts file should contain:
  ```
  [chia_farmer]
  chiamain ansible_host=192.168.1.10 
  chiaalts ansible_host=192.168.15.11

  [chia_harvester]
  harvester1 ansible_host=192.168.15.12
  harvester2 ansible_host=192.168.15.13

  [chia:children]
  chia_farmer
  chia_harvester
  ```

  ### 2. Specify blockchains/alt-chains and options

  Specify the blockchains a ansible host in `chia_farmer` group will run with `chia_blockchains` varible:

  ```
  chia_blockchains:
    - name: chia
      ip: <machinaris_controller IP>
      gpu: nvidia
      blockchain_db_download: yes           # See: https://github.com/guydavis/machinaris/wiki/Blockchains#blockchain-download
      blockchain_db_backup: yes             # Backup the blockchain sqlite db to persistent backup location
      machinaris_backup: yes                # Backup machinaris data to persistent backup, excluding sqlitedb and mnemonics
      disable_plot_check: yes               # See: https://github.com/guydavis/machinaris/wiki/Chia#check
      restore_blockchain_db: no             # Restore the sqlite DB from persistent backup if it doesn't exist already (deleted or new install)
  ```

  ### 3. Handling mnemonics

  The role leverages 1Password and uses the `op` command on the ansible controller shell. This can be installed with [1Password CLI][op-cli]

  A variable `chia_farmer_mnemonics` must be defined with how to get the seed phrase from 1Password:

  ```
  chia_farmer_mnemonics:
    - name: "XCH Mnenonic Seed"     # Name of your item in 1P
      field: "seed phrase"          # The field name containing seed phrase
      vault: "My Secret Vault"      # The name of 1P vault to get this from
  ```

  ### 4. Container data path

  Variable `chia_machinaris_data` must be specified with your root path to keep all Machinaris container persistent data:
  ```
  chia_machinaris_data: /opt/docker/data/machinaris
  ```

  ### 5. Machinaris controller IP

  The Machinaris primary controller IP (for the Chia fullnode) should be defined in a dictonary structure:
  ```
  chia_network:
    machinaris_controller: 
      ip: 192.168.15.20
  ```


## Optional configuration

  ### 1. Harvester Plots

  Specify a list of your plot directories with `chia_harvester_plots`

  ```
  chia_harvester_plots:
    - /mnt/plots1
    - /mnt/plots2
  ```

  It is expected these mounts are already configured on your system through another playbook/role

  ### 2. Docker/Container network configuration

  To create specific network for the Chia/Machinaris containers, a `docker_networks` variable must be defined

  ```
  docker_networks:
    miner_network:
      driver: macvlan
      driver_opts:
        parent: "{{ ansible_default_ipv4.interface }}"
      ipam:
        config:
          - subnet: 192.168.1.0/24
            gateway: 192.168.1.1
            ip_range: 192.168.1.0/24
  ```

  ### 3. Backup of container configuration and database

  For backup options to work, `persisten_backup` variable must be defined as a filesystem path

  `persistent_backup: /mnt/backups`


## Other

  ### Port Configurations

  Ports for each altchain are derived from https://www.machinaris.app/ and stored in `/vars/<mode>.yaml



[machinaris-git]: https://github.com/guydavis/machinaris
[op-cli]: https://developer.1password.com/docs/cli/get-started/
