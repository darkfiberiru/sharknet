#!/bin/sh
#
# Copyright (c) 2019 Nick Wolff (iXsystems) 
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
#
#
#=====SHARKNET=====
#This script creates a series of networks with basic services(dhcp,dns,routing) 
#Each network is designed to allow you to directly attach clients to a different interface on the FreeNAS
#This script only need run once to create any jails
#It will add init scripts and jail configs to recreate any resources needed on system reboot
#
#NETWORKING REQUIREMENTS:
#One external interface is needed and an additional internal interface per subnet/sharknet jail instance is needed. 
#The external interface does not have to be your external managment interface for the FreeNAS.
#If vlans are used please configure in UI prior running script
#If using vlan please set following on parent interface under options "-rxcsum -txcsum -tso4 -tso6 -rxcsum6 -txcsum6"
#Static routes are required on your router for the clients behind the FreeNAS to get out to the internet/Intranet.
#Without static routes the only advatange this plugin gives you is DHCP on each subnet
#
#CLEANUP:
#If you want to remove SHARKNET jails or run this script again you will need to:
#    -Destroy jails(Jails)
#    -Remove init scripts(Tasks->Init/Shutdown Scripts)
#    -unconfigure interfaces(Network->Interfaces) 
#The functionality for this script to clean up after itself in those area in very likely to be dangerous so it has not been implemented.
#
#SHARKNET Subnet Layout:
#FreeNAS = First ip in network 
#Client Default gateway = Second ip in network
#Clients = Rest of network excluding broadcast address
#
#
#TODO Features
#  * Nat for inside network/dhcp for jail external ip 
#  * Vpn setup (openvpn initial/zero tier later)
#==================
#set -xv

#CONFIGURATION SECTION

#zpool that iocage is using
pool="tank"
#Space seperated list of external dns server IP
#Clients will relay queries through each sharknet instance to these dns servers
dnsservers="10.215.1.8 8.8.8.8"
#External interface with inter/intranet connectivity
extinterface="vlan20"
#Default gateway for external interface
extdefault="10.20.20.1"
#Space seperated list of sharknet configs in format 'Internal Interface|External Ip/Subnetmask|Internal Network/Subnetmask'
#EXAMPLE: "igb0|192.168.0.2/24|172.16.0.0/24 igb2|192.168.0.3/24|172.16.1.0/24"
config="ixl0|10.20.20.160/23|10.215.11.0/26 ixl1|10.20.20.161/23|10.215.11.64/26 ixl2|10.20.20.162/23|10.215.11.128/26"

#END OF CONFIGURATION


#Add Post init tasks
postInit() {
  #TODO Automate with freenas api
  echo "Please add Post Init task \'${1}\'"
}
configureInterface() {
  #TODO Automate with freenas api
  echo "Please configure interface ${1} with ip ${2}"

}

#General system setup
initialSetup() {
  echo '{ "pkgs": [ "dnsmasq" ] }' > /tmp/sharknet-pkgs
  ifconfig bridge255 create addm ${extinterface} up
  postInit "ifconfig bridge255 create addm ${extinterface} up"
}

#Utility functions to deal with IPs
getNasIp() {
  #Take the network and return the NAS ip
  echo -e  "import ipaddress\nx=ipaddress.ip_network('${1}',False)\nprint('{}/{}'.format(x[1],x.prefixlen))"|python
}
getIntIp(){
  #Take the network and return the internal default gateway IP 
  echo -e  "import ipaddress\nx=ipaddress.ip_network('${1}',False)\nprint('{}/{}'.format(x[2],x.prefixlen))"|python
}
getNetwork() {
  #Take a network and verify you have the actual network address
  echo -e  "import ipaddress\nx=ipaddress.ip_network('${1}',False)\nprint(x)"|python
}
getFirstDhcp() {
  #Take a network and get the first IP for it's dhcp range
  echo -e  "import ipaddress\nx=ipaddress.ip_network('${1}',False)\nprint(x[3])"|python
}
getLastDhcp() {
  #Take a network and get the last IP for it's dhcp range
  echo -e  "import ipaddress\nx=ipaddress.ip_network('${1}',False)\nprint(x[-2])"|python
}

#Per Jail Setup
jailSetup() {
  i=${1}
  interface=${2}
  extip=${3}
  network="$( getNetwork ${4} )"
  intip="$( getIntIp ${network} )"
  nasip="$( getNasIp ${network} )"
  ifconfig bridge${i} create addm ${interface} up
  #TODO dnsmasq is not getting installed via pkg list need to fix
  iocage create -n sharknet${i} -r 11.2-RELEASE -p /tmp/sharknet-pkgs vnet=on \
    devfs_ruleset=2  ip4_addr="vnet0|${extip},vnet1|${intip}" interfaces="vnet0:bridge255,vnet1:bridge${i}"  \
	defaultrouter="${extdefault}" vnet_default_interface="${extinterface}"
  echo "Please setup a static route for network ${network} with the gateway ${extip} on your router"
  dns=""
  for server in ${dnsservers}; do
    dns="${dns} -S ${server}"
  done
  jailrc="/mnt/${pool}/iocage/jails/sharknet${i}/root/etc/rc.local"
  jailhosts="/mnt/${pool}/iocage/jails/sharknet${i}/root/etc/hosts"
  touch ${jailrc} 
  chmod +x ${jailrc} 
  #Turn on routing inside jail
  echo "$(echo ${nasip}|cut -d'/' -f1)		nas.local.ixsystems.com"  >> ${jailhosts}
  echo "$(echo ${intip}|cut -d'/' -f1)		sharknet${i}.local.ixsystems.com"  >> ${jailhosts}
  echo sysctl net.inet.ip.forwarding=1 >> ${jailrc}
  #Messed up pkg list above somehow. Workaround to fix that
  ASSUME_ALWAYS_YES=yes pkg install dnsmasq >> ${jailrc}
  first="$( getFirstDhcp ${network} )"
  last="$( getLastDhcp ${network} )"
  #Setup DNS and dhcp for internal network
  #The inside jail part of vnet1 interface is mapped as epair1b
  echo dnsmasq -i epair1b ${dns} --no-resolv  -F ${first},${last}  >> ${jailrc}
  #Full stop and start of jail to reload rc.local file
  iocage stop sharknet${i}
  iocage start sharknet${i}
  #TODO ASSIGN IP TO INTERFACE THROUGH FREENAS API
  echo "Please assign ip ${nasip} to  interface ${2} in the UI"
  postInit "ifconfig bridge${i} create addm ${interface} up"

}

main() {
 #Setup system		
 initialSetup
 i=0 
 #Setup each sharknet jail
 for entry in ${config}; do 
   i="$(echo ${i}+1|bc)"
   internalinterface="$(echo $entry |cut -d '|' -f1)"
   externalip="$(echo $entry |cut -d '|' -f2)"
   internalip="$(echo $entry |cut -d '|' -f3)"
   jailSetup ${i} ${internalinterface} ${externalip} ${internalip}
 done
}


main

