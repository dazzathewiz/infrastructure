### Setup WSL for Vagrant MAAS deploy
Because it wasn't simple

## Pre-requisits
1. Ensure the WSL Windows Role is ticked and installed in add/remove features
```
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all
```
2. Download "Ubuntu" app from the MS App Store and open/run it (terminal)


## Basic Usage
```
sudo ./install.sh
```
Close the terminal window and re-open

Run the run.yml ansible but add your sudo password to secret.yml with variable SUDO, first
```
ansible-vault create secret.yml
ansible-playbook run.yml
```

Example secret.yml:
```
SUDO: "yourpassword"
```

In PowerShell, restart your Ubuntu container:
```
Restart-Service -Name "LxssManager"
```

## What it does
Follow: https://github.com/deluxebrain/wsl-vagrant-hyperv-setup; getting this right can be painful first time.

1. Install Vagrant in WSL by deb package by wget, get URL from: https://releases.hashicorp.com/
2. Install the vagrant-reload plugin
3. Install Ansible from apt
4. Runs the run.yml ansible playbook to:
    a) modify ~/.profile and add these environment variables. Change HOME_PATH to suit your situation:
        ```
        # Enabled Vagrant Hyper-V Provider
        export VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH=/mnt/d/Repos
        export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1
        export VAGRANT_DEFAULT_PROVIDER=hyperv
        ```
    b) create or modify /etc/wsl.conf to add metadata flags to Windows /mnt paths (see: https://github.com/geerlingguy/ansible-for-devops/issues/234)
        ```
        # Enable extra metadata options by default
        [automount]
        enabled = true
        root = /mnt/
        options = "metadata,umask=77,fmask=11"
        mountFsTab = false
        ```


## Other troubleshooting
Check working as expected
```
vagrent --version
ansible --version
printenv | grep VAGRANT
cat /etc/wsl.conf
```

## Links
Useful information used to work out the working congfiguration
- https://github.com/deluxebrain/wsl-vagrant-hyperv-setup
- https://www.youtube.com/watch?v=7Di0twyxw1M
- https://github.com/hashicorp/vagrant/issues/11724
- https://github.com/geerlingguy/ansible-for-devops/issues/234
- https://www.schakko.de/2020/01/10/fixing-unprotected-key-file-when-using-ssh-or-ansible-inside-wsl/