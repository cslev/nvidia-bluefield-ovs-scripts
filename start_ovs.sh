#!/bin/bash
 
 ROOT="$(dirname "$0")"
 source $ROOT/sources/extra.sh
 
 
function show_help () 
 { 
 	c_print "Green" "This script stops Open vSwitch processes completely! Instead of a simple /etc/init.d/openvswitch-switch stop, this script systematically stop each individual subprocesses and removes OvS bridges and datapath components."
 	c_print "Bold" "Example: sudo ./stop_ovs.sh "
 	c_print "Bold" "\t-d: with DPDK (Default: NO)."
 	exit $1
 }

DPDK=""


while getopts "h?d:" opt
 do
 	case "$opt" in
 	h|\?)
 		show_help
 		;;
 	d)
 		DPDK=$OPTARG
 		;;
 
 	*)
 		show_help
 		;;
 	esac
 done


if [ -z $DPDK ]
then
  DPDK=0
 	c_print "Yellow" "Starting OVS without DPDK..."
  c_print "Bold" "Adding OVS kernel module" 1
  sudo modprove openvswitch 2>&1
  retval=$?
  check_retval $retval
else
  DPDK=1
  c_print "Yellow" "Starting OVS WITH DPDK..."
fi




DB_SOCK=/var/run/openvswitch
DB_SOCK="${DB_SOCK}/db.sock"

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
  c_print "Bold" "Initializing..." 1
  sudo ovs-vsctl --no-wait init
  retval=$?
  check_retval $retval

  c_print "Bold" "Starting vswitchd..." 
  sudo ovs-vswitchd unix:$DB_SOCK --pidfile=/var/run/openvswitch/ovs-vswitchd.pid --detach
  retval=$?
  check_retval $retval

#####################
##### OVS DPDK ######
#####################
else
  echo ""
fi

echo ""



