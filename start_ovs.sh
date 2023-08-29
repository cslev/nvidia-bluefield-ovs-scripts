#!/bin/bash
 
 ROOT="$(dirname "$0")"
 source $ROOT/sources/extra.sh
 
 
function show_help () 
 { 
 	c_print "Green" "This script stops Open vSwitch processes completely! Instead of a simple /etc/init.d/openvswitch-switch stop, this script systematically stop each individual subprocesses and removes OvS bridges and datapath components."
 	c_print "Bold" "Example: sudo ./stop_ovs.sh "
 	c_print "Bold" "\t-d: with DPDK (Default: NO)."
  c_print "Bold" "\t-o: enable HW OFFLOAD (Default: disable)."
 	exit $1
 }

DPDK=0
HW_OFFLOAD=0

while getopts "h?do" opt
 do
 	case "$opt" in
 	h|\?)
 		show_help
 		;;
 	d)
 		DPDK=1
 		;;
  o)
    HW_OFFLOAD=1
    ;;
 	*)
 		show_help
 		;;
 	esac
 done


if [ $HW_OFFLOAD -eq 0 ]
then
  c_print "Bold" "HW_OFFLOAD: DISABLED"
else
  c_print "Bold" "HW_OFFLOAD: ENABLED"
fi

if [ $DPDK -eq 0 ]
then
 	c_print "Yellow" "Starting OVS without DPDK..."
  c_print "Bold" "Adding OVS kernel module" 1
  sudo modprobe openvswitch 2>&1
  retval=$?
  check_retval $retval
else
  c_print "Yellow" "Starting OVS WITH DPDK..."
fi




DB_SOCK=/var/run/openvswitch
DB_SOCK="${DB_SOCK}/db.sock"

DBR="ovsbr1"
DBR2="ovsbr2"
DPDK_BR="ovs_dpdk_br0"


c_print "Bold" "Deleting preconfigured OvS data (/etc/openvswitch/conf.db)..." 1
sudo rm -rf /etc/openvswitch/conf.db > /dev/null 2>&1
c_print "BGreen" "[DONE]"


sudo mkdir -p /etc/openvswitch/
c_print "Bold" "Creating ovs database structure from template..." 1
sudo ovsdb-tool create /etc/openvswitch/conf.db  /usr/share/openvswitch/vswitch.ovsschema
retval=$?
check_retval $retval

sudo mkdir -p /var/run/openvswitch


c_print "Bold" "Starting ovsdb-server..." 1
sudo ovsdb-server --remote=punix:$DB_SOCK --remote=db:Open_vSwitch,Open_vSwitch,manager_options --pidfile=/run/openvswitch/ovsdb-server.pid --detach
retval=$?
check_retval $retval

####################
### OVS KERNEL #####
####################
if [ $DPDK -eq 0 ]
then
  c_print "Bold" "Setting other_config:dpdk-init=false" 1
  sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=false
  retval=$?
  check_retval $retval

  if [ $HW_OFFLOAD -eq 0 ]
  then
    c_print "Bold" "Setting other_config:hw-offload=false" 1
    sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:hw-offload=false
    retval=$?
    check_retval $retval
  else
    c_print "Bold" "Setting other_config:hw-offload=true" 1
    sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:hw-offload=true
    retval=$?
    check_retval $retval
  fi


  c_print "Bold" "Initializing..." 1
  sudo ovs-vsctl --no-wait init
  retval=$?
  check_retval $retval

  c_print "Bold" "Starting vswitchd..." 
  sudo ovs-vswitchd unix:$DB_SOCK --pidfile=/var/run/openvswitch/ovs-vswitchd.pid --detach
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding ovsbr1 bridge..." 1
  sudo ovs-vsctl add-br $DBR
  retval=$?
  check_retval $retval

  c_print "Bold" "Add physical port p0 to ovsbr1" 1
  sudo ovs-vsctl add-port $DBR p0
  retval=$?
  check_retval $retval

  c_print "Bold" "Add virtual port pf0hpf to ovsbr1" 1
  sudo ovs-vsctl add-port $DBR pf0hpf
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding ovsbr2 bridge..." 1
  sudo ovs-vsctl add-br $DBR2
  retval=$?
  check_retval $retval

  c_print "Bold" "Add physical port p0 to ovsbr1" 1
  sudo ovs-vsctl add-port $DBR2 p1
  retval=$?
  check_retval $retval

  c_print "Bold" "Add virtual port pf0hpf to ovsbr1" 1
  sudo ovs-vsctl add-port $DBR2 pf1hpf
  retval=$?
  check_retval $retval

  c_print "Bold" "Deleting NORMAL flow rules (if there were any) from the bridges..." 1
  sudo ovs-ofctl del-flows $DBR
  sudo ovs-ofctl del-flows $DBR2  
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding ARP flood flow rules to the bridges..." 
  sudo ovs-ofctl -OOpenFlow12 add-flow $DBR arp,actions=FLOOD
  sudo ovs-ofctl -OOpenFlow12 add-flow $DBR2 arp,actions=FLOOD
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding IP forward rule $DBR: ip,in_port=pf0hpf,ip_dst=10.0.0.2,ip_src=10.0.0.1,actions=output:p0..."  1  
  sudo ovs-ofctl -OOpenFlow13 add-flow $DBR ip,in_port=pf0hpf,ip_dst=10.0.0.2,ip_src=10.0.0.1,actions=output:p0
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding IP forward rule to $DBR: ip,in_port=p0,ip_dst=10.0.0.1,ip_src=10.0.0.2,actions=output:pf0hpf..."  1  
  sudo ovs-ofctl -OOpenFlow13 add-flow $DBR ip,in_port=p0,ip_dst=10.0.0.1,ip_src=10.0.0.2,actions=output:pf0hpf
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding IP forward rule $DBR2: ip,in_port=pf1hpf,ip_dst=10.10.10.2,ip_src=10.10.10.1,actions=output:p1..."  1  
  sudo ovs-ofctl -OOpenFlow13 add-flow $DBR2 ip,in_port=pf1hpf,ip_dst=10.10.10.2,ip_src=10.10.10.1,actions=output:p1
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding IP forward rule to $DBR2: ip,in_port=p1,ip_dst=10.10.10.1,ip_src=10.10.10.2,actions=output:pf1hpf..."  1  
  sudo ovs-ofctl -OOpenFlow13 add-flow $DBR2 ip,in_port=p1,ip_dst=10.10.10.1,ip_src=10.10.10.2,actions=output:pf1hpf
  retval=$?
  check_retval $retval



#####################
##### OVS DPDK ######
#####################
else
  echo ""
fi

echo ""



