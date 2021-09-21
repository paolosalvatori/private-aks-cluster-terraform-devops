#!/bin/bash

user=$1

# Eliminate debconf warnings
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Update the system
sudo apt-get update -y

# Upgrade packages
sudo apt-get upgrade -y

# Install kubectl
mkdir "/home/$user/.kube/" 
sudo snap install --classic kubectl

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash