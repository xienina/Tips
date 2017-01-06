#!/usr/bin/ksh
#
# CONFIG_FILE and SYSCONFIG_FILE templates are provided.
#

if [ $# = 0 ]; then
    echo "USAGE: $(basename ${.sh.file}) <zonename> <zoneip>"
    print "ERROR: missing options."
    exit 1
fi

ZONENAME=$1
ZONEIP=$2
if [[ -z $ZONENAME || -z $ZONEIP ]];then
    print "Both <zonename> and <zoneip> should be set"
    exit 1
fi    
DEFAULT_ROUTE=${ZONEIP%.*}.1

CONFIG_DIR=/net/oversteer/var/tmp/nina_web/nativezone
cp -r $CONFIG_DIR /root/  
CONFIG_FILE=/root/nativezone/nativezone.cfg
SYSCONFIG_FILE=/root/nativezone/sysconfig.xml
gsed -i "s/sct-t51b-07-kz5/$ZONENAME/" $SYSCONFIG_FILE
gsed -i "s/10.134.78.153/$ZONEIP/" $SYSCONFIG_FILE
gsed -i "s/10.134.78.1/$DEFAULT_ROUTE/" $SYSCONFIG_FILE

if zoneadm -z $ZONENAME list >/dev/null 2>&1; then
    zoneadm -z $ZONENAME halt >/dev/null 2>&1
    zonecfg -z $ZONENAME delete -F
    zfs destroy -r rpool/VARSHARE/zones/$ZONENAME
fi

if [[ -s $CONFIG_FILE && -s $SYSCONFIG_FILE ]]; then
    print "Start to configure/install $ZONENAME"
    zonecfg -z $ZONENAME -f $CONFIG_FILE
    zoneadm -z $ZONENAME install -c $SYSCONFIG_FILE
    zoneadm -z $ZONENAME boot
    print "\nStart to Add some packages in $ZONENAME"
    pkg -R /system/zones/$ZONENAME/root install pkg:/service/network/legacy-remote-utilities pkg:/service/network/legacy-network-services pkg:/text/gnu-sed pkg:/service/network/ntp pkg:/developer/build/make pkg:/text/gnu-grep pkg:/service/network/ftp pkg:/network/ftp pkg:/network/netcat expect pkg://solaris/network/telnet  pkg://solaris/service/network/telnet
else
    print "CONFIG_FILE or SYSCONFIG_FILE not exist!"    
    exit 1
fi


