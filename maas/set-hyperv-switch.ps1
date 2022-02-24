Get-VM "maas1" | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "Host Network"
Get-VM "maas1" | Set-VMNetworkAdapterVlan -Access -VlanId 900