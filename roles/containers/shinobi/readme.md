# Shinobi 
Shinobi docker container for ARM64:
- Uses image: [icebrian/shinobi-image][image]
- The [Shinobi-Systems][shinobigit] Git repo doesn't have ARM64 dockerfile

Note different to the x86 versions, using SpaceInvaderOne

## Usage
*Note: ```vars:``` are not required, although you probably need to change the ```container_network_ip``` for every installation

```
- role: containers/shinobi
      vars:
        container_network_vlan: 113
        container_network_subnet: 192.168.13.0/24
        container_network_ip: 192.168.13.6
        container_network_gateway: 192.168.13.1
      tags: containers
```
## References
- [Reddit][reddit] Post regarding use of ARM64 container image
- [spaceinvaderone/shinobi_pro_unraid][dockerhub]


[dockerhub]: https://hub.docker.com/r/spaceinvaderone/shinobi_pro_unraid
[shinobigit]: https://gitlab.com/Shinobi-Systems/Shinobi
[image]: https://hub.docker.com/r/icebrian/shinobi-image
[reddit]: [https://www.reddit.com/r/ShinobiCCTV/comments/iuh3np/shinobi_arm64_docker_image/]
