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
#  * Vpn setup (openvpn initial/zero tier later)
#  * Ipv6 support
#==================
#set -xv

#CONFIGURATION SECTION

#zpool that iocage is using
pool="tank"
#Space seperated list of external dns server IP
#Clients will relay queries through each sharknet instance to these dns servers
dnsservers="10.215.1.8 8.8.8.8"

#Command line argument is in format shown below
#Direct Config=:
#       "Internal Interface"
#Natted Config=:
#       "External Interface" "Internal Interface"
#Routed Config= Space seperated list of sharknet configs in format:
#       "External Interface     "External Ip/Subnetmask"     "External Default Route"   "Internal Interface"    "Internal Network/Subnetmask"
#EXAMPLE: "
#    igb2
#    vlan20 igb2
#    vlan20 192.168.0.2/24 igb0 172.16.0.0/24"
config="${1}|${2}|${3}|${4}|${5}"

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

createIntBridge() {
  interface="${1}"
  if ! ifconfig bridge-${1} ; then		
    bridge="$(ifconfig bridge create)"
    ifconfig ${bridge} name bridge-${interface} > /dev/null
    ifconfig bridge-${interface} addm ${interface} up > /dev/null
    postInit "sh -c \" bridge=\\\"\$(ifconfig bridge create)\\\"; ifconfig \${bridge} name bridge-${interface}; ifconfig bridge-${interface} addm ${interface} up"
  fi
}

#General system setup
initialSetup() {
  echo '{ "pkgs": [ "dnsmasq" ] }' > /tmp/sharknet-pkgs.json
  createIntBridge "$(echo ${config} | cut -d'|' -f1)"
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

createDnsmasqConfig() {
  network=${1}
  root=${2}
  first="$(getFirstDhcp ${network} )"
  last="$(getLastDhcp ${network} )"
  ASSUME_ALWAYS_YES=YES pkg -r ${root} -R ${root}/etc/pkg install dnsmasq >/dev/null
  dmconfig="${root}/usr/local/etc/dnsmasq.conf"
  mkdir -p $(dirname ${dmconfig})
  touch ${dmconfig}
  echo 'dnsmasq_enable="YES"' >> ${root}/etc/rc.conf
  echo interface=epair1b >> ${dmconfig}
  echo no-resolv >> ${dmconfig}
  for server in ${dnsservers}; do
    echo server=${server} >> ${dmconfig}
  done
  echo dhcp-range=${first},${last} >> ${dmconfig}
}

jailCommon() {
  interface="${1}"
  network="${2}"
  nasip="$( getNasIp ${network} )"
  root="/mnt/${pool}/iocage/jails/sharknet-${interface}/root"
  jailrc="${root}/etc/rc.local"
  jailhosts="${root}/etc/hosts"
  #Turn on routing inside jail
  echo sysctl net.inet.ip.forwarding=1 >> ${jailrc}
  echo "$(echo ${nasip}|cut -d'/' -f1)		nas.local.ixsystems.com"  >> ${jailhosts}
  echo "$(echo ${intip}|cut -d'/' -f1)		sharknet-${interface}.local.ixsystems.com"  >> ${jailhosts}
  #Setup DNS and dhcp for internal network
  #The inside jail part of vnet1 interface is mapped as epair1b so we don't need to pass it to dnsmasq
  createDnsmasqConfig ${network} ${root}
  #Start of jail to load rc.local file
  iocage stop sharknet-${interface}
  iocage start sharknet-${interface}
  configureInterface ${interface} ${nasip}
}

jailRoutedSetup() {
  network="$( getNetwork $(echo ${config}|cut -d'|' -f5) )"
  intiface="$( echo ${config}|cut -d'|' -f4)"
  extiface="$( echo ${config}|cut -d'|' -f1)"
  extip="$( echo ${config}|cut -d'|' -f1)"
  extdefault="$(echo ${config}|cut -d'|' -f3)"
  intip="$( getIntIp ${network} )"
  createIntBridge ${intiface}
  iocage create -n sharknet${i} -r 11.2-RELEASE -p /tmp/sharknet-pkgs.json vnet=on \
    devfs_ruleset=2  ip4_addr="vnet0|${extip},vnet1|${intip}" interfaces="vnet0:bridge-${extiface},vnet1:bridge-${intiface}"  \
	defaultrouter="${extdefault}" vnet_default_interface="${extiface}"
  jailrc="/mnt/${pool}/iocage/jails/sharknet-${intiface}/root/etc/rc.local"
  touch ${jailrc} 
  chmod +x ${jailrc} 
  echo "Please setup a static route for network ${network} with the gateway ${extip} on your router"
  jailCommon ${intiface} ${network} 
}

generateRndNet() {
  second=$(jot -r 1 16 32)
  third=$(jot -r 1 4 250)
  echo "172.${second}.${third}.0/24"
}


jailNatSetup() {
  extiface="$(echo ${config}|cut -d'|' -f1)"
  intiface="$(echo ${config}|cut -d'|' -f2)"
  network="$(generateRndNet)" 
  intip="$( getIntIp ${network} )"
  createIntBridge ${intiface}
  iocage create -n sharknet-${intiface} -r 11.2-RELEASE vnet=on \
    devfs_ruleset=2  ip4_addr="none" interfaces="vnet0:bridge-${extiface},vnet1:bridge-${intiface}" bpf=yes \
    dhcp=on vnet_default_interface="none" defaultrouter="none"
  jailrc="/mnt/${pool}/iocage/jails/sharknet-${intiface}/root/etc/rc.local"
  jailrcconf="/mnt/${pool}/iocage/jails/sharknet-${interface}/root/etc/rc.conf"
  jaildhclient="/mnt/${pool}/iocage/jails/sharknet-${interface}/root/etc/dhclient.conf"
  touch ${jailrc} 
  chmod +x ${jailrc} 
  kldload ipfw
  #Bad network hacks to handle older iocage
  echo timeout 8 >> ${jaildhclient}
  echo pkill -f epair1b >> ${jailrc}
  echo ifconfig epair1b -alias >> ${jailrc}
  echo ifconfig epair1b ${intip} >> ${jailrc}
  #nat config
  echo sysctl net.inet.ip.fw.default_to_accept=1 >> ${jailrc}
  echo sysctl net.inet.ip.fw.enable=1 >> ${jailrc}
  #NATCONFIG borrowed and tweaked from iocage ioc_start.py Brandon Schneider @skarekrow
  #'-tso4', '-lro', '-vlanhwtso'
  echo "ipfw -q nat 462 config if epair1b same_ports" >> ${jailrc}
  echo "ipfw -q add 100 nat 462 ip4 from not me to any out via epair1b" >> ${jailrc} 
  echo "ipfw -q add 101 nat 462 ip4 from any to any in via epair1b" >> ${jailrc}
  jailCommon ${intiface} ${network}

}

jailDirectSetup() {
  intiface="$(echo ${config}|cut -d'|' -f1)"
  network="$(generateRndNet)" 
  echo ${network}
  intip="$( getIntIp ${network} )"
  createIntBridge ${intiface}
  #Need to figure out how to fetch package so I can avoid outside network needs
  iocage create -n sharknet-${intiface} -r 11.2-RELEASE vnet=on \
    devfs_ruleset=2  ip4_addr="vnet1|${intip}" interfaces="vnet1:bridge-${intiface}" bpf=yes \
    vnet_default_interface="none" defaultrouter="none"
  jailrc="/mnt/${pool}/iocage/jails/sharknet-${intiface}/root/etc/rc.local"
  jailrcconf="/mnt/${pool}/iocage/jails/sharknet-${interface}/root/etc/rc.conf"
  touch ${jailrc} 
  chmod +x ${jailrc} 
  jailCommon ${intiface} ${network}

}


main() {
  #Setup system
  if [ "?${1}" != "?" ] ; then
    echo "Please supply atleast 1 argument if your doing a direct config"
    exit
  fi
  initialSetup
  if [ "?${4}" != "?" ] ; then
    jailRoutedSetup
  elif [ "?${2}" != "?" ] ; then
    jailNatSetup
  else
    jailDirectSetup
  fi
}


main $@

