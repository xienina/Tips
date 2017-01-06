#!/usr/bin/ksh
# 
# For solaris s11u3+ os network diagnose and setup.
#
function usage {
	cat <<EOF_USAGE
	Usage:  set_net -i <interface> -d <location> | -a <dns server> [-b] [-c] [-h]
	OPTONS:
		-i the control interface link name.
		-d the location of target machine, please refer to  
		   $dns_wiki if your machine location not list here.
		   In set_net, it can be set to: us, cn, bu, br, na, te, ut.
           		us - U.S. West (including HQ, Santa Clara, and SLDC)
           		cn - China
           		bu - Burlington1/3/5/6 (only)
           		br - Broomfield
           		na - Nashua NEDC Only
           		tx - Austin Data Center (Texas)
           		ut - Utah Compute Facility (UCF)
		-a the dns servers you want to specify manually. 
		   The -a option is exclusive with -d.	
		-b create a backup BE before the fix
		-c check network only, does not do any fix
		-h help
	EXAMPLES:
		set_net -i net0 -d us
		set_net -i net0 -a "10.210.76.197 10.210.76.198 195.135.80.132"

	NOTE: set_net is to set up/fix networking configuration issues. It will
	do the following:
	1) Set up the IP on the given interface via DHCP
	2) Set up the default route, which is <subnet>.1
	3) Disable other interfaces if they seem to be causing routing issues
	4) Setup DNS/LDAP per oracle defaults

EOF_USAGE
}

function error {
	print "stderr| $1 - FAIL"
	if $CHECK_NETWORK_ONLY; then
		exit 1
	fi
}

function info {
	print "stdout| $1"
}

function enable_service {
	# usage: enable_service <fmri>
	# this function is to enable service and check service status
	# <fmri> is service name
	typeset -i timer=60
	typeset -i i=0
	typeset fmri=$1
	typeset ss=$(svcs -Ho STATE $fmri)
	
	#Restart on-line service to make service refresh thoroughly 
	if [[ $ss == online || $ss == degraded ]]; then
		svcadm restart -s -T 5 $fmri
	elif [[ $ss == disabled || $ss == offline ]]; then
		svcadm enable -rs $fmri
	elif [[ $ss == maintenance ]]; then
		svcadm clear $fmri
	fi
	while (( $timer > 0 )); do
		if [[ $(svcs -Ho STATE $fmri) == online ]]; then
			info "$fmri is online" 
			return 0
		fi
		if [[ $(svcs -Ho STATE $fmri) == degraded ]]; then
			info "$fmri is degraded"
			return 0
		fi
		if [[ $(svcs -Ho STATE $fmri) == maintenance ]]; then
			svcadm clear $fmri
			i=$((i+1))
			if (( $i == 2 )); then
				error "clear $fmri from maintenance"
				return 1
			fi
		fi
		timer=$((timer-2))
		sleep 2
	done
	if (( $timer <= 0 )); then
		error "cleared service $fmri with 60s"
		return 1
	fi
}

function ping_test {
	# ping_test $1
	# this function is to verify ping some ip addresses work or not
	# <fun> is the function name or operation description
	typeset fun=$1
	typeset ping_timeout=3
	if ping $TESTIP1 $ping_timeout >/dev/null 2>&1; then
		if ping $TESTIP2 $ping_timeout >/dev/null 2>&1; then
			info "$fun - PASS"
			return 0
		else
			info "$fun - FAIL"
			error "ping $TESTIP2"
			return 1
		fi
	else
		info "$fun - FAIL"
		error "ping $TESTIP1"
		return 1
	fi
}

function create_BE {
	# create a backup BE before do any operation
	typeset currentBE backupBE tm
	tm=$(date +%m%d_20%y_%H%M)
	currentBE=$(beadm list | awk '{if ($2 == "NR" || $2 == "N") print $1}')
	backupBE=${currentBE}.set_net.${tm}

	beadm create $backupBE >/dev/null 2>&1
	if (( $? == 0 )); then
		info "Create a backup BE for $currentBE named $backupBE"
		return 0
	else
		error "Create backup BE $backupBE"
		return 1
	fi
}

function set_defaultroute {
	# set_defaultroute <nic>
	# set_defaultroute is to get the missing default route.
	# We assume the control interface use /24 as subnet mark.
	typeset nic=$1 addr mask
	set -A default_route $(netstat -rn | grep default | awk '{print $2}')
	addr=$(ipadm show-addr -po ADDR $nic|awk -F/ '{print $1}' |head -1)
	mask=$(ipadm show-addr -po ADDR $nic|awk -F/ '{print $2}' |head -1)
	typeset pre=${addr%.*}
	
	if [[ $mask != 24 ]]; then
		error "$nic subnet mask /$mask not supported"
		info "this script only support to configure subnet mask /24"
		return 1
	fi
	netstat -rn | grep default >/dev/null 2>&1
	ret=$?
	if [[ $ret == 0 && ${default_route[0]} != ${pre}.1 ]]; then
		error "Default route is not correct"
		info "Adding new default route"
		if (( ${#default_route[@]} > 1 )); then
			error "Multiple default routes found" 
		fi
		info "Deleting default routes"
		for i in ${default_route[*]}
		do
			route delete default $i >/dev/null
		done
		route -p add default ${pre}.1 >/dev/null 2>&1
		if (( $? != 0 )); then
			error "Add default route"
			return 1
		else
			info "Default route is added.\n"
		fi
	elif (( $ret != 0 )); then
		error "Default route not exist"
		info "Adding new default route"

		route -p add default ${pre}.1 >/dev/null 2>&1
		if (( $? != 0 )); then
			error "Add default route"
			return 1
		else
			info "Default route is added.\n"
		fi
	else
		info "Default route is existing"
		return 1
	fi

	# check whether the ping works well now
	ping_test "Fix default route issue"
	return $?	

}

function check_ifs {
	# Check whether multiple interfaces impact the network
	typeset nic=$1
	typeset traceroute_file=/tmp/traceroute_$$
	set -A ifnames $(ipadm show-if -po IFNAME |egrep -v "lo0|$nic")

	traceroute -Q 1 -m 1 -w 2 $TESTIP1 >$traceroute_file 2>&1
	grep "Multiple interfaces" $traceroute_file >/dev/null 2>&1
	# sometimes someone create-addr on other nic but with
	# different subnet mask with control-interface
	if (( $? == 0 )); then
		info "Multiple interfaces found"
		info "Disabling the other interfaces..."
		for i in ${ifnames[*]}
		do
			info "Disable $i temporarily"
			ipadm disable-if -t $i
		done
		ping_test "Fix interfaces issue TEMPORARILY"
		ret=$?
		if (( $ret == 0)); then
			error "Existing incorrect address in \"${ifnames[*]}\""
			info "You can delete them for PERSISTENT fix"
		fi
		return $ret
	else
		return 1
	fi
}

function set_ipaddr {
	# set_ipaddr <nic>
	# configure the NIC dhcp ip-address
	typeset nic=$1 mac
	typeset ipadm_bk="/var/tmp/ipadm.set_net"
	info "Starting to configure $nic dhcp ip-address"
	info "Will save the original interfaces info to $ipadm_bk"
	ipadm > $ipadm_bk
	ipadm delete-ip $nic >/dev/null 2>&1
	ipadm create-ip $nic
	if (( $? != 0 )); then
		error "Is $nic a valid device link name, create-ip $nic"
		return 1
	fi
	info "Getting the dhcp address for $nic"
	ipadm create-addr -T dhcp $nic/v4dhcp  >/dev/null 2>&1
	if (( $? != 0 )); then
		mac=`dladm show-phys -m $nic`
		info "CAN NOT get dhcp ip-address on $nic, or:\n \
		    1. Is this machine registered with $nic MAC=$mac?\n \
		    2. Is the NIC $nic the right control interface?\n"
		error "Create dhcp ip-address"
		return 1
	fi
	ipadm show-addr $nic | grep "$nic/v4dhcp" | grep ok > /dev/null
	(( $? == 0 )) && info "$nic dhcp ip-address is created"
	ping_test "Fix set_ipaddr"
	return $?
}

function fix_ping {
	# fix_ping <nic>
	# fix_ping will call set_defaultroute, set_ipaddr, ping_test
	# fix_ping is to fix ping related issues
	typeset nic=$1
	info "Check PING - Start"
	ping_test "Try to ping $TESTIP1 and $TESTIP2"
	(( $? == 0 )) && info "Check PING - PASS\n" && return 0
	info "Try to find ping issue ..."
	if ipadm show-addr $nic >/dev/null 2>&1; then
		set_defaultroute $nic || check_ifs $nic
		if (( $? == 0)); then
			info "Fix PING - PASS\n"
			return 0
		fi
		set_ipaddr $nic
		return $?
	else
		set_ipaddr $nic
		return $?	
	fi

}

function fix_autofs {
	typeset pwd_dir=$(pwd)
	typeset nfs_path=/net/tas.us.oracle.com/export/projects/
	info "Check autofs - Start"
	enable_service svc:/system/filesystem/autofs:default
	timeout 10 cd $nfs_path >/dev/null 2>&1 && cd $pwd_dir \
            >/dev/null 2>&1
        if (( $? != 0 )); then
		info "cd $nfs_path - FAIL"
		return 1
	else
		info "Check autofs - PASS\n"
		return 0
        fi
	
}

function fix_dns {
	# fix_dns is to setup/fix dns client related issues
	typeset ret1 ret2
	typeset ping_timeout=3
	info "Check DNS - Start"
	getent hosts $TESTHOST1 >/dev/null 2>&1 && getent hosts \
	    $TESTHOST2 >/dev/null 2>&1
	ret1=$?
        ping $TESTHOST1 $ping_timeout >/dev/null 2>&1
	ret2=$?
	if (( $ret1 == 0 && $ret2 == 0 )); then
                info "Check DNS - PASS\n"
                return 0
	else
		if (( $ret1 != 0 )); then
			error "getent hosts $TESTHOST1 and $TESTHOST2"
		fi
		if (( $ret2 != 0 )); then
			error "ping $TESTHOST1"
		fi
		info "Try to reconfigure DNS ..."

		svcadm disable -s svc:/network/dns/client:default
		svcadm disable -s system/name-service/switch
		
		svccfg -s network/dns/client setprop \
		    config/search = astring: \
		    \($DNS_SEARCH\)
		svccfg -s network/dns/client setprop \
		    config/nameserver = net_address: \
		    \($DNS_SERVERS\)
		svccfg -s network/dns/client refresh

		svccfg -s system/name-service/switch setprop \
		    config/host = astring: '"files dns"'
		svccfg -s system/name-service/switch setprop \
		    config/default = astring: '"files ldap"'
		svccfg -s system/name-service/switch refresh
	 
		enable_service network/dns/client
		enable_service system/name-service/switch

		if getent hosts $TESTHOST1 >/dev/null 2>&1 && getent \
	    	    hosts $TESTHOST2 >/dev/null 2>&1; then
			info "Fix DNS - PASS\n" 
			return 0
		else
			error "Fix DNS"
			return 1
		fi
	fi

}

function init_ldap_old {
	info "Initiating ldapclient with old situations ... "
	[[ -s /var/ldap/ ]] || mkdir -m 777 /var/ldap
	if [[ $DOMAIN = us ]]; then
		ldapclient init -a profilename=CR-sol-sca -a \
		    domainname=oracle.com -a \
		    proxyDN="cn=sun_admin,ou=adminusers,dc=oracle,dc=com" -a \
		    proxyPassword=sunds4sun cr-lc-sfbay-01.us.oracle.com
		return $?
	elif [[ $DOMAIN = cn ]]; then
		ldapclient init -a profilename=CR-sol-zpk -a \
		    domainname=oracle.com -a \
		    proxyDN="cn=sun_admin,ou=adminusers,dc=oracle,dc=com" -a \
		    proxyPassword=sunds4sun lc-cbjs-01.oraclecorp.com
		return $?
	fi
}

function init_ldap {
	# call the tool oraldap to setup ldap
	info "try to reconfigure LDAP, may need a few minutes ... "
	typeset ldapscript=/net/bonn-b.us.oracle.com/export/pool-1/dleavitt/oraldap/oraldap.sh
	echo yes | $ldapscript uninit-siteprofile >/dev/null 2>&1
	[[ -d /var/ldap/ ]] || mkdir -m 777 /var/ldap
	if [[ -f /etc/nsswitch.conf && ! -f /etc/nsswitch.conf.set_net ]]; then 
		mv /etc/nsswitch.conf /etc/nsswitch.conf.set_net
	fi
	$ldapscript init-ldapswitch >/dev/null 2>&1
	info "You can choose profile with: $ldapscript list-profiles"
	info "Initiating ldapclient with profile CR-sca-tls ..."
	$ldapscript init-pam
	$ldapscript init-cert
	$ldapscript init CR-sca-tls >/dev/null
	return $?
}

function fix_ldap {
	# fix_ldap is to setup/fix ldap client related issues
	info "Check LDAP - Start"	
	typeset -i ret1 ret2
	typeset -i timer=10
	if [[ $(svcs -Ho STATE autofs) != online ]]; then
		error "Autofs is not online"
		info "enable autofs now"
		enable_service svc:/system/filesystem/autofs:default
	fi
	timeout $timer ldaplist auto_ws on12-gate >/dev/null 2>&1 
	ret1=$?
	timeout $timer ls /ws/on12-gate/packages/$(uname -p) >/dev/null 2>&1
	ret2=$?
	if (( $ret1 == 0 && $ret2 == 0 )); then
		# "ldaplist auto_ws on12-gate" check sometimes not so accurate
		info "Check LDAP - PASS\n"
		return 0
	else
		error "Access /ws/on12-gate/packages/$(uname -p)"
		if init_ldap; then
			info "init_ldap pass"
		elif init_ldap_old; then
			info "init_ldap_old pass"
		else
			error "init_ldap and init_ldap_old"
			return 1
		fi
		enable_service network/dns/client
		enable_service system/name-service/switch
		enable_service svc:/network/nis/domain:default
		enable_service svc:/network/ldap/client:default
		enable_service svc:/system/filesystem/autofs:default
		sleep 2	
		ls /ws/on12-gate/packages/$(uname -p) >/dev/null 2>&1
		if (( $? == 0 )); then
			info "Fix LDAP - PASS\n"
			return 0
		else
			error "Fix LDAP"
			return 1
		fi
	fi

}

############################### MAIN #################################
# Please set the following vars by yourself.
TESTIP1=x.x.x.x
TESTIP2=x.x.x.x
TESTHOST1=xx
TESTHOST2=xx
DNS_SEARCH='"sina.com" "baidu.com" "hah.com"'
dns_wiki="http://xxx/site/git/xxx/xxx/xxx/index.html"
############################### 

CHECK_NETWORK_ONLY=false
DFLAG=0
AFLAG=0
DOMAIN=ip

while getopts ":i:d:a:bch" flag; do
	case $flag in
		i) NIC=$OPTARG
			;;
		d) DOMAIN=$OPTARG
			DFLAG=1
			;;
		a) DNS_SERVERS=$OPTARG
			AFLAG=1
			;;
		b) create_BE
			;;
		c) CHECK_NETWORK_ONLY=true
			;;
		h)	usage
			exit 0
			;;
		:) print "ERROR: missing option:-$OPTARG argument\n"
			usage
			exit 1
			;;
		?) print "ERROR: invalid option $OPTARG"
			usage
			exit 1
			;;
		*)	usage
			exit 1 
			;;

	esac
done

case $DOMAIN in
	us) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x"  # please set to the real dns you need to use.
		;;
	cn) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x" 
		;;
	bu) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x" 
		;;
	br) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x" 
		;;
	na) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x" 
		;;
	te) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x" 
		;;
	ut) DNS_SERVERS="x.x.x.x  x.x.x.x  x.x.x.x" 
		;;
	ip) 
		;;	
	*) print "ERROR: '$DOMAIN' is not supported in this script"
		usage
		exit 1
		;;
esac

shift $(($OPTIND-1))
if (( $# > 0 )); then
	usage
	exit 1
fi

if [[ -z $NIC ]]; then
	print "ERROR: missing mandatory option -i <interface>"
	usage
	exit 1
fi

if (( $DFLAG+$AFLAG != 1 )); then
	print "ERROR: -a and -d are mandatory options, but exclusive"
	usage
	exit 1
fi

print "******************************************************"
print "You will setup/fix network with DOMAIN=$DOMAIN, CONTROL_INTERFACE=$NIC"
print "******************************************************\n"

if [[ `id -u` -ne 0 ]]; then
	error "Please re-run set_net script as root"
	exit 1
fi

# start to setup/recover network on local machine
fix_ping $NIC || exit 1
fix_dns || exit 1
fix_autofs || exit 1
fix_ldap || exit 1
info "Network Works Well on $(hostname)!\n"
