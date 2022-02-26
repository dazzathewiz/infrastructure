# MaaS server auto deploy on Hyper-V

## Requirements
1. A Hyper-V Windows host with the Hyper-V role installed
2. A Hyper-V Virtual Switch called "Host Network", connected to a network port trunked with VLAN 900 (specifc to my environment)
3. Vagrant installed https://www.vagrantup.com/downloads
4. vagrant-reload is installed ``` vagrant plugin install vagrant-reload ```
5. Setup WSL: see ./setup_wsl folder
6. (WSL specific) The Vagrantfile directory (repo) must be located on within path set in VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH environment variable

## Basic Startup
Using Windows Subsystem for Linux (WSL) 
1. Start the Ubuntu app (WSL) - make sure you "Run as Administrator" on Windows (required for Hyper-V provider)
2. Create/Checkout the Vagrantfile to a subfolder of VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH
3. ``` vagrant up ```
IMPORTANT: You will be asked to choose a switch to attach to the VM. Ensure you choose: Default Switch, even though the machine will be put on a different switch, this will be done as part of provisioning in Vagrantfile

## Teardown
```
vagrant destroy
```

## Configuration
VM Hostname     -> change in Vagrantfile, and set-hyperv-switch.ps1
VM IP address   -> change in configure-static-ip.sh
VM Network/VLAN -> change in set-hyperv-switch.ps1

## WSL and other 'gotchas'
Make sure your Vagrantfile (this repo) is checked out within VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH environment variable. If this variable is not setup in your environment, see ./setup_wsl folder for more information.

You can link your source from (VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH) /mnt/{drive}/{path} to ~/source -?> see: https://github.com/hashicorp/vagrant/issues/11724
EG:
```
ln -s /mnt/c/Users/Daz/infrastructure ~/source
```

Make sure vagrant-reload is installed in the WSL environment as well as the Hyper-V Windows host