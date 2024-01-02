#!/bin/bash
 
 ROOT="$(dirname "$0")"
 source $ROOT/sources/extra.sh
 
 
function show_help () 
 { 
 	c_print "Green" "This script starts Open vSwitch processes manually! Instead of a simple /etc/init.d/openvswitch-switch start, this script systematically start each individual subprocess and creates OvS bridges and datapath components."
 	c_print "Bold" "Example: sudo ./start_ovs.sh "
 	c_print "Bold" "\t-d: with DPDK (Default: NO)."
  c_print "Bold" "\t-o: enable HW OFFLOAD (Default: disable)."
  c_print "Bold" "\t-t: use two bridges (ovsbr1 + ovsbr2) (Default: False (ovsbr1 only))."
 	exit $1
 }

DPDK=0
HW_OFFLOAD=0
TWO_BRIDGES=0

while getopts "h?dot" opt
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
  t)
    TWO_BRIDGES=1
    ;;
 	*)
 		show_help
 		;;
 	esac
 done

c_print "None" "+========= YOUR SETTINGS ===========+"
if [ $HW_OFFLOAD -eq 0 ]
then
  c_print "Bold" "|  HW_OFFLOAD: DISABLED"
else
  c_print "Bold" "|  HW_OFFLOAD: ENABLED"
fi
c_print "None" "+-----------------------------------+"

if [ $DPDK -eq 0 ]
then
 	c_print "Bold" "|  DPDK: NO"
  # c_print "Bold" "Adding OVS kernel module" 1
  sudo modprobe openvswitch 2>&1
  retval=$?
  check_retval $retval
else
  c_print "Bold" "| DPDK: YES"
fi
c_print "None" "+===================================+"


LOG_OVS_DB=/var/log/openvswitch/cslev-ovsdb-server.log
LOG_OVS_VSCTL=/var/log/openvswitch/cslev-ovs-vsctl.log
LOG_OVS_VSWITCHD=/var/log/openvswitch/cslev-ovs-vswitchd.log

PID_OVSDB=/var/run/openvswitch/ovsdb-server.pid
PID_OVS_VSWITCHD=/var/run/openvswitch/ovs-vswitchd.pid

DBR="ovsbr1"
DBR2="ovsbr2"
DPDK_BR="ovs_dpdk_br0"

# these following two paths decide many other paths
VSWITCH_SCHEMA_PATH_OPTION_1=/usr/share/openvswitch/vswitch.ovsschema
VSWITCH_SCHEMA_PATH_OPTION_2=/usr/local/share/openvswitch/vswitch.ovsschema
#check which path is right for vswitchd.schema
if [ -f $VSWITCH_SCHEMA_PATH_OPTION_1 ]
then
  #this is the case when OvS is installed from repository
  VSWITCH_SCHEMA=$VSWITCH_SCHEMA_PATH_OPTION_1
  CONF_DB_PATH="/etc/openvswitch/conf.db"
  DB_SOCK=/var/run/openvswitch
  DB_SOCK="${DB_SOCK}/db.sock"
elif [ -f $VSWITCH_SCHEMA_PATH_OPTION_2 ]
then
  #this is the case when OvS compiled from source
  VSWITCH_SCHEMA=$VSWITCH_SCHEMA_PATH_OPTION_2
  CONF_DB_PATH="/usr/local/etc/openvswitch/conf.db"
  DB_SOCK=/usr/local/var/run/openvswitch
  DB_SOCK="${DB_SOCK}/db.sock"
else
  c_print "Red" "vswitch.schema file not found..."
  exit
fi




c_print "Bold" "Deleting preconfigured OvS data (/etc/openvswitch/conf.db)..." 1
sudo rm -rf $CONF_DB_PATH > /dev/null 2>&1
c_print "BGreen" "[DONE]"


sudo mkdir -p $(dirname $CONF_DB_PATH)
c_print "Bold" "Creating ovs database structure from template..." 1
sudo ovsdb-tool create $CONF_DB_PATH $VSWITCH_SCHEMA
retval=$?
check_retval $retval

sudo rm -rf $(dirname $DB_SOCK)
sudo rm -rf $(dirname $LOG_OVS_DB)
sudo mkdir -p $(dirname $DB_SOCK)
sudo mkdir -p $(dirname $LOG_OVS_DB)



c_print "Bold" "Starting ovsdb-server..." 1
sudo ovsdb-server --remote=punix:$DB_SOCK --remote=db:Open_vSwitch,Open_vSwitch,manager_options --pidfile=$PID_OVSDB --log-file=$LOG_OVS_DB --detach
retval=$?
check_retval $retval

####################
### OVS KERNEL #####
####################

c_print "Bold" "Initializing..." 1
sudo ovs-vsctl --no-wait --log-file=$LOG_OVS_VSCTL init 

retval=$?
check_retval $retval


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

  c_print "Bold" "Starting vswitchd..." 
  sudo ovs-vswitchd unix:$DB_SOCK --pidfile=$PID_OVS_VSWITCHD --log-file=$LOG_OVS_VSWITCHD --detach
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

  if [ $TWO_BRIDGES -eq 1 ]
  then
    c_print "Bold" "Adding second ovsbr2 bridge..." 1
    sudo ovs-vsctl add-br $DBR2
    retval=$?
    check_retval $retval
 
    c_print "Bold" "Add physical port p1 to ovsbr2" 1
    sudo ovs-vsctl add-port $DBR2 p1
    retval=$?
    check_retval $retval

    c_print "Bold" "Add virtual port pf1hpf to ovsbr2" 1
    sudo ovs-vsctl add-port $DBR2 pf1hpf
    retval=$?
    check_retval $retval
  else
    c_print "Bold" "Add physical port p1 to ovsbr1" 1
    sudo ovs-vsctl add-port $DBR p1
    retval=$?
    check_retval $retval

    c_print "Bold" "Add virtual port pf1hpf to ovsbr1" 1
    sudo ovs-vsctl add-port $DBR pf1hpf
    retval=$?
    check_retval $retval
  fi

  c_print "Bold" "Deleting NORMAL flow rules (if there were any) from the bridges..." 1
  sudo ovs-ofctl del-flows $DBR

  if [ $TWO_BRIDGES -eq 1 ]
  then
    sudo ovs-ofctl del-flows $DBR2  
    retval=$?
    check_retval $retval
  fi

  c_print "Bold" "Adding ARP flood flow rules to the bridges..." 
  sudo ovs-ofctl -OOpenFlow12 add-flow $DBR arp,actions=FLOOD
  if [ $TWO_BRIDGES -eq 1 ]
  then
    sudo ovs-ofctl -OOpenFlow12 add-flow $DBR2 arp,actions=FLOOD
    retval=$?
    check_retval $retval
  fi
  
  c_print "Bold" "Adding port forward rule to $DBR (fwd direction): ip,in_port=pf0hpf,actions=output:p0" 1  
  sudo ovs-ofctl -OOpenFlow13 add-flow $DBR ip,in_port=pf0hpf,actions=output:p0
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding port forward rule to $DBR (rev direction): ip,in_port=p0,actions=output:pf0hpf"  1  
  sudo ovs-ofctl -OOpenFlow13 add-flow $DBR ip,in_port=p0,actions=output:pf0hpf
  retval=$?
  check_retval $retval

  if [ $TWO_BRIDGES -eq 1 ]
  then
    c_print "Bold" "Adding port forward rule to $DBR2 (fwd direction): ip,in_port=pf1hpf,actions=output:p1..."  1  
    sudo ovs-ofctl -OOpenFlow13 add-flow $DBR2 ip,in_port=pf1hpf,actions=output:p1
    retval=$?
    check_retval $retval

    c_print "Bold" "Adding port forward rule to $DBR2 (rev direction): ip,in_port=p1,actions=output:pf1hpf..."  1  
    sudo ovs-ofctl -OOpenFlow13 add-flow $DBR2 ip,in_port=p1,actions=output:pf1hpf
    retval=$?
    check_retval $retval
  else
    c_print "Bold" "Adding port forward rule to $DBR (fwd direction): ip,in_port=pf1hpf,actions=output:p1" 1  
    sudo ovs-ofctl -OOpenFlow13 add-flow $DBR ip,in_port=pf1hpf,actions=output:p1
    retval=$?
    check_retval $retval

    c_print "Bold" "Adding port forward rule to $DBR (rev direction): ip,in_port=p1,actions=output:pf1hpf"  1  
    sudo ovs-ofctl -OOpenFlow13 add-flow $DBR ip,in_port=p1,actions=output:pf1hpf
    retval=$?
    check_retval $retval
  fi

 



#####################
##### OVS DPDK ######
#####################
else
  c_print "Yellow" "Verify your hugepage settings..." 
  for HUGEPAGE in $(sudo mount |grep hugetlb|awk '{print $3}')
  do
    umount $HUGEPAGE
  done 

  # c_print "Bold" "Enabling 2M hugepages..." 1
  # #sudo echo 8192 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
  sudo echo 11280 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
  retval=$?
  check_retval $retval

  c_print "Bold" "Mounting hugepages..." 1
  sudo mkdir /mnt/huge -p
  mount -t hugetlbfs nodev /mnt/huge
  # #sudo mountpoint -q /dev/hugepages || sudo mount -t hugetlbfs nodev /dev/hugepages
  retval=$?
  check_retval $retval


  c_print "Bold" "Setting other_config:dpdk-init=true" 1
  sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true 
  retval=$?
  check_retval $retval

  c_print "Bold" "Setting dpdk lcore mask=0xff" 1
  sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-lcore-mask=0xff
  retval=$?
  check_retval $retval

  c_print "Bold" "Setting dpdk socket mem 4096" 1
  sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="4096"
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


  c_print "Bold" "Starting vswitchd..." 
#  sudo ovs-vswitchd unix:$DB_SOCK --pidfile=/var/run/openvswitch/ovs-vswitchd.pid --log-file=/var/run/openvswitch/ovs-vswitchd.log --detach
  sudo ovs-vswitchd unix:$DB_SOCK --log-file=$LOG_OVS_VSWITCHD --detach

  retval=$?
  check_retval $retval

  c_print "Bold" "Creating DPDK netdev bridge..." 1
  sudo ovs-vsctl add-br $DPDK_BR -- set bridge $DPDK_BR datapath_type=netdev
  retval=$?
  check_retval $retval

  c_print "Bold" "Adding DPDK ports as other_config params..." 1
  # sudo ovs-vsctl set Open_vSwitch . other_config:dpdk-extra="-a 0000:03:00.0,representor=[0,65535] -a 0000:03:00.1,representor=[0,65535]"
  sudo ovs-vsctl set Open_vSwitch . other_config:dpdk-extra="-a 0000:03:00.0,representor=[0,65535]"

  retval=$?
  check_retval $retval

  c_print "Bold" "Adding 0000:03:00.0 as port dpdk0 to ${DPDK_BR}..." 1
  sudo ovs-vsctl --no-wait add-port $DPDK_BR dpdk0 -- set Interface dpdk0 type=dpdk -- set Interface dpdk0 options:dpdk-devargs=0000:03:00.0
  retval=$?
  check_retval $retval

  # c_print "Bold" "Adding 0000:03:00.0's virtual function (VF) as port dpdk1 to ${DPDK_BR}..." 1
  # sudo ovs-vsctl --no-wait add-port $DPDK_BR dpdk1 -- set Interface dpdk1 type=dpdk -- set Interface dpdk1 options:dpdk-devargs=0000:03:00.0,representor=[65535]
  # retval=$?
  # check_retval $retval

  # c_print "Bold" "Adding 0000:03:00.1 as port dpdk2 to ${DPDK_BR}..." 1
  # sudo ovs-vsctl --no-wait add-port $DPDK_BR dpdk2 -- set Interface dpdk2 type=dpdk -- set Interface dpdk2 options:dpdk-devargs=0000:03:00.1
  # retval=$?
  # check_retval $retval

  # c_print "Bold" "Adding 0000:03:00.1's virtual function (VF) as port dpdk3 to ${DPDK_BR}..." 1
  # sudo ovs-vsctl --no-wait add-port $DPDK_BR dpdk3 -- set Interface dpdk3 type=dpdk -- set Interface dpdk3 options:dpdk-devargs=0000:03:00.1,representor=[0,65535]
  # retval=$?
  # check_retval $retval

fi

echo ""



