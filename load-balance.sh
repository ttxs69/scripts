#!/bin/bash

# Load balance multiple internet connections. Requires iproute2, awk and grep.
# (C) 2016 Tobias Girstmair, isticktoit.net, GPLv2
# Also useful: speedometer -l  -r eth1 -t eth1 -m $(( 1024 * 1024 * 3 / 2 ))
# Not much user error checking is done - only pass working network connections

# script needs root to work and at least two interfaces to be useful
[ $EUID -eq 0 -a $# -ge 2 ] || {
	echo "Usage (as root): $0 iface1[:weight1] iface2[:weight2] ..." >&2
	exit 1
}

get_free_tblnum() { # http://stackoverflow.com/a/28702075
	awk -v RS='\\s+' '{ a[$1] } END { for(i = 10; i in a; ++i); print i }'</etc/iproute2/rt_tables
}

loadbal() {
	IFS=':' read IFACE WEIGHT <<< "$1"
	TABLE="${IFACE}loadbalance"
	if ! grep -q -w "$TABLE" /etc/iproute2/rt_tables ; then
		echo "$(get_free_tblnum) $TABLE" >> /etc/iproute2/rt_tables
	fi
	MY_IP=$(ip -o -4 addr show $IFACE |awk -F'(\\s|/)+' '{print $4}')
	GW_IP=$(ip route show dev $IFACE | awk '/default/ {print $3}')
	SUBNT=$(ip route show dev $IFACE | awk '/proto kernel/ {print $1}')

	ip route add $SUBNT dev $IFACE src $MY_IP table $TABLE
	test -n "$GW_IP" && ip route add default via $GW_IP table $TABLE
	ip rule add from $MY_IP table $TABLE
	test -n "$GW_IP" && echo nexthop via $GW_IP dev $IFACE weight ${WEIGHT:-1}
}

ip route add default scope global $(for IF in "$@"; do loadbal $IF; done)
