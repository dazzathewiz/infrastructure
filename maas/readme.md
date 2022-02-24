# MaaS server auto deploy on Hyper-V

## Requirements
1. A Hyper-V Windows host with the Hyper-V role installed
2. A Hyper-V Virtual Switch called "Host Network", connected to a network port trunked with VLAN 900 (specifc to my environment)
3. Vagrant installed https://www.vagrantup.com/downloads
4. vagrant-reload is installed ``` vagrant plugin install vagrant-reload ```

## Basic Startup
PowerShell.exe run as Administrator:
```
vagrant up
```
IMPORTANT: You will be asked to choose a switch to attach to the VM. Ensure you choose: Default Switch, even though the machine will be put on a different switch, this will be done as part of provisioning in Vagrantfile

## Teardown
```
vagrant destroy
```

## Configuration
VM Hostname     -> change in Vagrantfile, and set-hyperv-switch.ps1
VM IP address   -> change in configure-static-ip.sh
VM Network/VLAN -> change in set-hyperv-switch.ps1