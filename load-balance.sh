#!/bin/bash

# Load balance multiple internet connections. Requires iproute2, awk and grep.
# (C) 2016 Tobias Girstmair, isticktoit.net, GPLv2
# Also useful: speedometer -l  -r eth1 -t eth1 -m $(( 1024 * 1024 * 3 / 2 ))
# Not much user error checking is done - only pass working network connections

# script needs root to work and at least two interfaces to be useful
[ $EUID -eq 0 -a $# -eq 2 ] || {
	echo "Usage (as root): $0 [interface] [number]" >&2
	exit 1
}

get_free_tblnum() { # http://stackoverflow.com/a/28702075
	awk -v RS='\\s+' '{ a[$1] } END { for(i = 10; i in a; ++i); print i }'</etc/iproute2/rt_tables
}

loadbal() {
	IFACE="veth$1"
	TABLE="${IFACE}loadbalance"
	NUM="$(get_free_tblnum)" 
	if ! grep -q -w "$TABLE" /etc/iproute2/rt_tables ; then
		echo "$NUM $TABLE" >> /etc/iproute2/rt_tables
	fi
	MY_IP=$(ip -o -4 addr show $IFACE |awk -F'(\\s|/)+' '{print $4}')
	echo "MY_IP:$MY_IP"
	SUBNT=$(ip route show dev $IFACE | awk '/proto kernel/ {print $1}')

	#ip route add $GW_IP dev $IFACE src $MY_IP table $TABLE
	ip route add table $TABLE default dev $IFACE via $GW_IP 	
	ip rule add fwmark "0x${NUM}" table $TABLE pref $NUM
	ip rule add from $MY_IP lookup $TABLE pref `expr $NUM + 100`

	# 新建 $TABLE 链
	iptables -t mangle -N $TABLE
	iptables -t mangle -A $TABLE -j MARK --set-mark "0x${NUM}"
	iptables -t mangle -A $TABLE -j CONNMARK --save-mark  # copy packet-mark to connect-mark

	# 应用至 OUTPUT 链
	iptables -t mangle -A OUTPUT -o "veth+" -p tcp -m state --state NEW -m statistic --mode nth --every $TOTAL --packet $1 -j $TABLE
	iptables -t mangle -A OUTPUT -o "veth+" -p udp -m state --state NEW -m statistic --mode nth --every $TOTAL --packet $1 -j $TABLE
	iptables -t mangle -A OUTPUT -o "veth+" -p icmp -m state --state NEW -m statistic --mode nth --every $TOTAL --packet $1 -j $TABLE
	
	# 应用至 PREROUTING 链
	iptables -t mangle -A PREROUTING -p tcp -m state --state NEW -m statistic --mode nth --every $TOTAL --packet $1 -j $TABLE
	iptables -t mangle -A PREROUTING -p udp -m state --state NEW -m statistic --mode nth --every $TOTAL --packet $1 -j $TABLE
	iptables -t mangle -A PREROUTING -p icmp -m state --state NEW -m statistic --mode nth --every $TOTAL --packet $1 -j $TABLE	
}


dhclient -nw
sleep 5
FACE=$1
TOTAL=$2
END=`expr $2 - 1`
GW_IP=$(ip route show| awk '/default/ {print $3}')
echo "GW_IP:$GW_IP"
if [ ! $GW_IP ]; then
	echo "Not found GW_IP!";
	exit;
fi
dhclient -r
for i in $(seq 0 $END);
do
	ip link add link $FACE dev "veth$i" type macvlan
done
dhclient -nw
sleep 5
for i in $(seq 0 $END); 
do 
	loadbal $i;
done
iptables -t mangle -A PREROUTING -p tcp -m state --state ESTABLISHED,RELATED -j CONNMARK --restore-mark # copy connect-mark to packet-mark
iptables -t mangle -A PREROUTING -p udp -m state --state ESTABLISHED,RELATED -j CONNMARK --restore-mark # copy connect-mark to packet-mark
iptables -t mangle -A PREROUTING -p icmp -m state --state ESTABLISHED,RELATED -j CONNMARK --restore-mark # copy connect-mark to packet-mark
iptables -t mangle -A OUTPUT -o "veth+" -p  tcp -m state --state ESTABLISHED,RELATED -j CONNMARK --restore-mark # copy connect-mark to packet-mark
iptables -t mangle -A OUTPUT -o "veth+" -p  udp -m state --state ESTABLISHED,RELATED -j CONNMARK --restore-mark # copy connect-mark to packet-mark
iptables -t mangle -A OUTPUT -o "veth+" -p  icmp -m state --state ESTABLISHED,RELATED -j CONNMARK --restore-mark # copy connect-mark to packet-mark
# 对内网流量进行 SNAT
iptables -t nat -A POSTROUTING -o "veth+" -j MASQUERADE
