# DietPi
Setup DietPi with essential config for homelab environment

## Requirements
1. A Raspberry Pi with https://dietpi.com/ image
2. DietPi must be booted and completed setup
3. OpenSSH server installed (not default), or an alternative that enables SCP and SFTP
4. Default user: dietpi and known password
5. Python 3 Pip installed (dietpi-software 130), required for ansible to work

I configure the above in the SD card image from: https://github.com/dazzathewiz/mac-raspberrypi-bootstrap

## Dependancies
dietpi role assumes default user: 'dietpi' and will reset the password of this account during configuration with password specified in 'infadmin_password' variable.
Ensure you have group_vars/secret.yml setup with 'infadmin_password'. 

The dietpi role depends on 'common' role to reset the password of 'dietpi', but leaves password authentication enabled.

## Functionality
Simply performs update and sets the timezone if not already set.
