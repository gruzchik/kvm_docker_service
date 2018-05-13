#!/bin/bash
SCRIPTPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

virsh net-destroy external
virsh net-destroy internal
virsh net-destroy management

cp ${SCRIPTPATH}/networks/external.xml /etc/libvirt/qemu/networks/external.xml
cp ${SCRIPTPATH}/networks/internal.xml /etc/libvirt/qemu/networks/internal.xml
cp ${SCRIPTPATH}/networks/management.xml /etc/libvirt/qemu/networks/management.xml
virsh net-undefine external
virsh net-undefine internal
virsh net-undefine management


#rm /etc/libvirt/qemu/networks/external.xml
#rm /etc/libvirt/qemu/networks/internal.xml
#rm /etc/libvirt/qemu/networks/management.xml

virsh destroy vm1
virsh undefine vm1
virsh destroy vm2
virsh undefine vm2

#rm -rf /var/lib/libvirt/images/vm1
#rm -rf /var/lib/libvirt/images/vm2
virsh pool-destroy vm1
#virsh pool-delete vm1
virsh pool-undefine vm1
virsh pool-destroy vm2
#virsh pool-delete vm2
virsh pool-undefine vm2
