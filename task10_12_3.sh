#!/bin/bash

SCRIPTPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# enable config file
source ${SCRIPTPATH}/config

echo vm1=${VM1_NAME}
echo vm2=${VM2_NAME}

#create xml external network and start net
[ ! -d ${SCRIPTPATH}/networks ] && mkdir -p ${SCRIPTPATH}/networks
MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`
cat <<EOF > ${SCRIPTPATH}/networks/external.xml
<network>
    <name>${EXTERNAL_NET_NAME}</name>
    <forward mode='nat'>
      <nat>
        <port start='1024' end='65535'/>
      </nat>
    </forward>
    <ip address='${EXTERNAL_NET_HOST_IP}' netmask='${EXTERNAL_NET_MASK}'>
      <dhcp>
        <range start='${EXTERNAL_NET}.2' end='${EXTERNAL_NET}.254' />
        <host mac='${MAC}' name='${VM1_NAME}' ip='${VM1_EXTERNAL_IP}'/>
      </dhcp>
    </ip>
  </network>
EOF

virsh net-define ${SCRIPTPATH}/networks/external.xml
#virsh net-create ${EXTERNAL_NET_NAME}
virsh net-autostart ${EXTERNAL_NET_NAME}
virsh net-start ${EXTERNAL_NET_NAME}

#create xml internal network and start net
cat <<EOF > ${SCRIPTPATH}/networks/internal.xml
<network>
    <name>${INTERNAL_NET_NAME}</name>
  </network>
EOF

virsh net-define ${SCRIPTPATH}/networks/internal.xml
virsh net-autostart ${INTERNAL_NET_NAME}
virsh net-start ${INTERNAL_NET_NAME}

#create xml management network and start net
cat <<EOF > ${SCRIPTPATH}/networks/management.xml
<network>
    <name>${MANAGEMENT_NET_NAME}</name>
  </network>
EOF

virsh net-define ${SCRIPTPATH}/networks/management.xml
virsh net-autostart ${MANAGEMENT_NET_NAME}
virsh net-start ${MANAGEMENT_NET_NAME}

## create disk for vm1
#VM1_HDD_PATH=$(dirname ${VM1_HDD})
#[ ! -d ${VM1_HDD_PATH} ] && mkdir -p ${VM1_HDD_PATH}
#echo "qemu-img create -f qcow2 ${VM1_HDD} 5Gb"
#qemu-img create -f qcow2 ${VM1_HDD} 5G

# prepare disk for vm1 and vm2
VM1_HDD_PATH=$(dirname ${VM1_HDD})
[ ! -d ${VM1_HDD_PATH} ] && mkdir -p ${VM1_HDD_PATH}
VM2_HDD_PATH=$(dirname ${VM2_HDD})
[ ! -d ${VM2_HDD_PATH} ] && mkdir -p ${VM2_HDD_PATH}

if [ ! -x "$(command -v wget)" ]; then
	apt-get install -y wget
fi

if [ ! -f /var/lib/libvirt/images/xenial-server-cloudimg-amd64-disk1-template.qcow2 ]; then
	wget -O /var/lib/libvirt/images/xenial-server-cloudimg-amd64-disk1-template.qcow2 ${VM_BASE_IMAGE}
fi
cp -f /var/lib/libvirt/images/xenial-server-cloudimg-amd64-disk1-template.qcow2 ${VM1_HDD}
cp -f /var/lib/libvirt/images/xenial-server-cloudimg-amd64-disk1-template.qcow2 ${VM2_HDD}

# starting configuration for vm1
#ssh-keygen -t rsa -f $HOME/.ssh/id_rsa3 -q -N ""
[ ! -d ${SCRIPTPATH}/config-drives/vm1-config ] && mkdir -p ${SCRIPTPATH}/config-drives/vm1-config
# meta-data vm1
cat <<EOF > ${SCRIPTPATH}/config-drives/vm1-config/meta-data
instance-id: iid-abcdefg
hostname: vm1
network-interfaces: |

  auto ${VM1_EXTERNAL_IF}
  allow-hotplug ${VM1_EXTERNAL_IF}
  iface ${VM1_EXTERNAL_IF} inet dhcp

  auto ${VM1_INTERNAL_IF}
  iface ${VM1_INTERNAL_IF} inet static
  address ${VM1_INTERNAL_IP}
  netmask ${INTERNAL_NET_MASK}

  auto ${VM1_MANAGEMENT_IF}
  iface ${VM1_MANAGEMENT_IF} inet static
  address ${VM1_MANAGEMENT_IP}
  netmask ${MANAGEMENT_NET_MASK}
EOF

# user-data vm1
cat <<EOF > ${SCRIPTPATH}/config-drives/vm1-config/user-data
#cloud-config
ssh_authorized_keys:
  - $(cat  $SSH_PUB_KEY)
runcmd:
  - ip link add ${VXLAN_IF} type vxlan id ${VID} remote ${VM2_INTERNAL_IP} local ${VM1_INTERNAL_IP} dstport 4789
  - ip link set ${VXLAN_IF} up
  - ip addr add ${VM1_VXLAN_IP}/24 dev ${VXLAN_IF}
  - echo "1" > /proc/sys/net/ipv4/ip_forward
  - iptables -t nat -I POSTROUTING -o ${VM1_EXTERNAL_IF} -j MASQUERADE
  - apt-get update
  - apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable"
  - apt-get update
  - apt-get install -y docker-ce
  - hostname vm1
  - mount /dev/cdrom /mnt
  - cp -aR /mnt/docker/certs/* /etc/ssl/certs/
  - docker run -t -i -d -p ${NGINX_PORT}:80 --name mir_nginx -v /etc/ssl/certs:/etc/ssl/certs -v /mnt/docker/etc/nginx.conf:/etc/nginx/nginx.conf -v ${NGINX_LOG_DIR}:/var/log/nginx ${NGINX_IMAGE}
EOF

# starting configuration for vm2
[ ! -d ${SCRIPTPATH}/config-drives/vm2-config ] && mkdir -p ${SCRIPTPATH}/config-drives/vm2-config
# meta-data vm2
cat <<EOF > ${SCRIPTPATH}/config-drives/vm2-config/meta-data
instance-id: iid2-abcdefg
hostname: vm2
network-interfaces: |
  auto ${VM2_INTERNAL_IF}
  iface ${VM2_INTERNAL_IF} inet static
  address ${VM2_INTERNAL_IP}
  netmask ${INTERNAL_NET_MASK}
  gateway ${VM1_INTERNAL_IP}
  dns-nameservers ${VM_DNS}

  auto ${VM2_MANAGEMENT_IF}
  iface ${VM2_MANAGEMENT_IF} inet static
  address ${VM2_MANAGEMENT_IP}
  netmask ${MANAGEMENT_NET_MASK}
EOF

# user-data vm2
cat <<EOF > ${SCRIPTPATH}/config-drives/vm2-config/user-data
#cloud-config
#password: xenial
#chpasswd: { expire: False }
#ssh_pwauth: True
ssh_authorized_keys:
  - $(cat  $SSH_PUB_KEY)
runcmd:
  - ip link add ${VXLAN_IF} type vxlan id ${VID} remote ${VM1_INTERNAL_IP} local ${VM2_INTERNAL_IP} dstport 4789
  - ip link set ${VXLAN_IF} up
  - ip addr add ${VM2_VXLAN_IP}/24 dev ${VXLAN_IF}
  - apt-get update
  - apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable"
  - apt-get update
  - apt-get install -y docker-ce
  - docker run -t -i -d -p ${APACHE_PORT}:80 --name mir_apache ${APACHE_IMAGE}
EOF

# generate root certificate
[ ! -d ${SCRIPTPATH}/docker/certs ] && mkdir -p ${SCRIPTPATH}/docker/certs

SSL_SCRIPTPATH="${SCRIPTPATH}/docker/certs"
openssl genrsa -out ${SSL_SCRIPTPATH}/root-ca.key 2048
openssl req -x509 -days 365 -new -nodes -key ${SSL_SCRIPTPATH}/root-ca.key -sha256 -out ${SSL_SCRIPTPATH}/root-ca.crt -subj "/C=UA/ST=Kharkiv/L=Kharkiv/O=Nure/OU=Admin/CN=rootCA"
# generate nginx cert
openssl genrsa -out ${SSL_SCRIPTPATH}/web.key 2048
openssl req -nodes -new -sha256 -key ${SSL_SCRIPTPATH}/web.key -out ${SSL_SCRIPTPATH}/web.csr -subj "/C=UA/ST=Kharkiv/L=Kharkiv/O=Datacenter/OU=Server/CN=${VM1_NAME}"
openssl x509 -req -extfile <(printf "subjectAltName=IP:${VM1_EXTERNAL_IP},DNS:www.${VM1_NAME}") -days 365 -in ${SSL_SCRIPTPATH}/web.csr -CA ${SSL_SCRIPTPATH}/root-ca.crt -CAkey ${SSL_SCRIPTPATH}/root-ca.key -CAcreateserial -out ${SSL_SCRIPTPATH}/web.crt

# add SSL_CHAIN
cat ${SSL_SCRIPTPATH}/web.crt ${SSL_SCRIPTPATH}/root-ca.crt > ${SSL_SCRIPTPATH}/web-bundle.crt
cp -aR ${SCRIPTPATH}/docker/certs/* /etc/ssl/certs/
SSL_KEY="/etc/ssl/certs/web.key"
SSL_CHAIN="/etc/ssl/certs/web-bundle.crt"

# generate nginx.conf file
[ ! -d ${SCRIPTPATH}/docker/etc ] && mkdir -p ${SCRIPTPATH}/docker/etc
cat <<EOF > ${SCRIPTPATH}/docker/etc/nginx.conf
worker_processes 1;
#daemon off;
events {
    worker_connections 1024;
}
http {
        error_log /var/log/nginx/error.log;
        access_log /var/log/nginx/access.log;
        server {
	    #listen          80;
	    listen 80 ssl;
            ssl on;
            ssl_certificate ${SSL_CHAIN};
            ssl_certificate_key ${SSL_KEY};
            server_name     nginx;
            location / {
                proxy_pass  http://${VM2_VXLAN_IP}:${APACHE_PORT};
            }
        }
}
EOF

# create iso for vm1 and vm2
cp -aR ${SCRIPTPATH}/docker ${SCRIPTPATH}/config-drives/vm1-config/
mkisofs -o "${VM1_CONFIG_ISO}" -V cidata -r -J ${SCRIPTPATH}/config-drives/vm1-config
mkisofs -o "${VM2_CONFIG_ISO}" -V cidata -r -J ${SCRIPTPATH}/config-drives/vm2-config

# create vm1
echo 'create vm1...'
virt-install \
--connect qemu:///system \
--name ${VM1_NAME} \
--ram ${VM1_MB_RAM} --vcpus=${VM1_NUM_CPU} --${VM_TYPE} \
--os-type=linux --os-variant=generic \
--disk path=${VM1_HDD},format=qcow2,bus=virtio,cache=none \
--disk path=${VM1_CONFIG_ISO},device=cdrom \
--network network=${EXTERNAL_NET_NAME},mac=${MAC} \
--network network=${INTERNAL_NET_NAME} \
--network network=${MANAGEMENT_NET_NAME} \
--graphics vnc,port=-1 \
--noautoconsole --quiet --virt-type "${VM_VIRT_TYPE}" --import
echo 'wait 10 sec..'
sleep 10
# create vm2
echo 'create vm2...'
virt-install \
--connect qemu:///system \
--name ${VM2_NAME} \
--ram ${VM2_MB_RAM} --vcpus=${VM2_NUM_CPU} --${VM_TYPE} \
--os-type=linux --os-variant=generic \
--disk path=${VM2_HDD},format=qcow2,bus=virtio,cache=none \
--disk path=${VM2_CONFIG_ISO},device=cdrom \
--network network=${INTERNAL_NET_NAME} \
--network network=${MANAGEMENT_NET_NAME} \
--graphics vnc,port=-1 \
--noautoconsole --quiet --virt-type "${VM_VIRT_TYPE}" --import
