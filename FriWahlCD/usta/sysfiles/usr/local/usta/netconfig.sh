#!/bin/bash

#
# $Id: netconfig.sh 456 2011-01-16 10:52:52Z mariop $
#

netcfgdir=/etc/network.d

while true ; do
    dlgopt=()
    for f in $netcfgdir/* ; do
	[ -f "$f" ] || continue
	name=`grep "DESCRIPTION=" $f | sed 's/DESCRIPTION=//g' | sed 's/"//g'`
	dlgopt=("${dlgopt[@]}" `basename $f` "$name")
    done
    dlgopt=("${dlgopt[@]}" manual "Manuelle Einrichtung (Experten)")
    choice=$(dialog \
    	--stdout \
	--backtitle "FriWahl" \
	--title "Netzwerk-Einrichtung" \
	--ok-label "Ok" \
	--menu "Bitte die Netzwerk-Einrichtung auswählen:" \
	0 0 0 "${dlgopt[@]}") || exit 0

    for devdir in /sys/class/net/*; do
        dev=`echo $devdir | sed "s|/sys/class/net/||g"`
        if [ `cat $devdir/type` = "1" ]; then
            ip link set $dev down
        fi
    done

    if [ "$choice" == manual ] ; then
    	./manualnet.sh
	exit 0
    else
	netcfg -a
        # TODO fix device name!
	ip link set eth0 up
	echo "waiting for device eth0"
	for i in `seq 1 20`; do sleep 1; echo -n "."; done
	echo
	netcfg $choice
        exit 0
    fi
done

