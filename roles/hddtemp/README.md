c1.hddtemp
==========

Ansible role to install and setup the hddtemp hard disk temperature monitoring daemon.

Role Variables
--------------

see defaults/main.yml

Example Playbook
----------------

    - hosts: servers
      roles:
         - { role: hddtemp, hddtemp_run_daemon: yes }

License
-------

BSD
