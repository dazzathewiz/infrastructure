# MaaS server auto deploy on Hyper-V

## Requirements
1. A Hyper-V Windows host with the Hyper-V role installed
2. A Hyper-V Virtual Switch called "Host Network", connected to a network port trunked with VLAN 900 (specifc to my environment)
3. Vagrant installed https://www.vagrantup.com/downloads
4. vagrant-reload is installed ``` vagrant plugin install vagrant-reload ```
5. Setup WSL: https://www.youtube.com/watch?v=7Di0twyxw1M - see more detailed setup below

## Basic Startup
Using Windows Subsystem for Linux (WSL)
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

## WSL Setup
Follow: https://github.com/deluxebrain/wsl-vagrant-hyperv-setup; getting this right can be painful first time.
1. Ensure the WSL Windows Role is ticked and installed in add/remove features
2. Download "Ubuntu" app from the MS App Store
3. Start the Ubuntu app (WSL) - make sure you "Run as Administrator" on Windows (required for Hyper-V provider)
4. modify ~/.profile and add these environment variables. Change HOME_PATH to suit your situation:
```
# Enabled Vagrant Hyper-V Provider
export VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH=/mnt/d/Repos
export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1
export VAGRANT_DEFAULT_PROVIDER=hyperv
```
5. Make sure your Vagrantfile (this repo) is checked out within HOME_PATH specified in step 4 /mnt/{drive}/{path} -?> see: https://github.com/hashicorp/vagrant/issues/11724
EG:
```
ln -s /mnt/d/Repos/ ~/source
```
6. Make sure vagrant-reload is installed in the WSL environment as well as the Hyper-V Windows host