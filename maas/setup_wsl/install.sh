#!/bin/sh

# Ensure up-to-date
sudo apt update
sudo apt upgrade

# Install Vagrant manually - you can update the URL to latest available here: https://releases.hashicorp.com/vagrant/
wget https://releases.hashicorp.com/vagrant/2.2.19/vagrant_2.2.19_x86_64.deb
sudo apt install ./vagrant_2.2.19_x86_64.deb

# Install Vagrent reload plugin
vagrant plugin install vagrant-reload

# Install ansible
sudo apt install ansible