#!/bin/sh
ip link add link enp2s0 dev veth0 type macvlan mode private
ip link add link enp2s0 dev veth1 type macvlan mode private

