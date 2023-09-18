#!/bin/bash
 
 ROOT="$(dirname "$0")"
 source $ROOT/sources/extra.sh
 
 
function show_help () 
 { 
 	c_print "Green" "This script stops Open vSwitch processes completely! Instead of a simple /etc/init.d/openvswitch-switch stop, this script systematically stop each individual subprocess and removes OvS bridges and datapath components."
 	c_print "Bold" "Example: sudo ./stop_ovs.sh "
 	#c_print "Bold" "\t-a <ARG1>: set ARG1 here (Default: ???)."
 	exit $1
 }

ARG1=""


while getopts "h?a:" opt
 do
 	case "$opt" in
 	h|\?)
 		show_help
 		;;
 	# a)
 	# 	ARG1=$OPTARG
 	# 	;;
 
 	*)
 		show_help
 		;;
 	esac
 done


DB_SOCK=/var/run/openvswitch
DB_SOCK="${DB_SOCK}/db.sock"

DBR="ovsbr1"
DBR2="ovsbr2"
DPDK_BR="ovs_dpdk_br0"


c_print "Bold" "Checking if OVS is running..."
sudo ps aux |grep ovs|grep -v grep
retval=$?
if [ $retval -ne 0 ]
then
	c_print "Yellow" "OVS is not running, nothing to do..."
	c_print "None" "Exiting..."
	exit 0
fi

# if [ -z $ARG1 ]
#  then
#  	c_print "Red" "Undefined arguments!"
#  	show_help
#  fi



c_print "Bold" "Removing 'ovsbr1', 'ovsbr2', and 'ovs_dpdk_br0' bridges if they exist..." 1
sudo ovs-vsctl --if-exists del-br $DBR 
sudo ovs-vsctl --if-exists del-br $DBR2 
sudo ovs-vsctl --if-exists del-br $DPDK_BR
retval=$?
# c_print "Red" "Retval: ${retval}"
check_retval $retval 1

# c_print "Bold" "Removing default DP in kernel..." 1
# sudo ovs-dpctl del-dp system@ovs-system
# retval=$?
# check_retval $retval 1



c_print "Bold" "Killing the whole process tree of OVS" 1
sudo pkill ovsdb-server
sudo pkill ovs-vswitchd
retval=$?
check_retval $retval 1


c_print "Bold" "Removing OVS kernel module" 1
sudo rmmod openvswitch 2>/dev/null
retval=$?
check_retval $retval 1

# c_print "Bold" "Removing hugepages (if any)" 1
# sudo rm -rf /mnt/huge/*
# sudo umount /mnt/huge
# sudo echo 0 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
# retval=$?
# check_retval $retval 1


c_print "Bold" "\n\nAfter all these, I find the following processes still running that might be related to OvS. Please, check!"
ps aux |grep ovs|grep -v "grep --color=auto" |grep -v "stop_ovs.sh"|grep -v "grep ovs"|grep -v "nano"


echo -e "\n"



