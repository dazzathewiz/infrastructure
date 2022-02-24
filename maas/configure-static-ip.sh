#!/bin/sh

echo 'Setting static IP address for Hyper-V...'

cat << EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses: [10.10.0.5/24]
      gateway4: 10.10.0.1
      nameservers:
        addresses: [192.168.10.53,192.168.10.153]
EOF