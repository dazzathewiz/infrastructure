# docker_compose Role

## Example: machinaris containers
```
- role: containers/docker_compose
  vars:
    container_use_git: true
    container_git: 
      repo: https://github.com/dazzathewiz/chia-forks.git
      name: chia-forks
      subpath: "{{ inventory_hostname }}"
      version: storecrypt
  tags: containers,test
```