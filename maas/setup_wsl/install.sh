#!/bin/sh

# Ensure up-to-date
apt update
apt upgrade

# Install Vagrant manually - you can update the URL to latest available here: https://releases.hashicorp.com/vagrant/
wget -P ~/ https://releases.hashicorp.com/vagrant/2.2.19/vagrant_2.2.19_x86_64.deb
apt install ~/vagrant_2.2.19_x86_64.deb

# Install Vagrent reload plugin
vagrant plugin install vagrant-reload

# Install ansible
apt install ansible

# Run ansible playbook to configure wsl
ansible-playbook -i ../../hosts ../../setup-wsl-for-hyperv.yml --ask-become-pass