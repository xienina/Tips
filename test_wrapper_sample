#!/usr/bin/ksh
#
# This is a temporary test script for security crypto part test cases of java regression.
# 
# export PS4='+{${.sh.file}:${.sh.fun}:$LINENO} ' && set -x

TSTAMP=$(date +%m%d_20%y_%H%M)
SAVE_DIR=/net/tas/export/projects/Security/java_crypto
SAVE_LOG=${SAVE_DIR}/$(uname -v).$(isainfo -n).$(hostname).$TSTAMP
SUMMARY="$SAVE_LOG/mail.summary"

function usage
{
	cat <<EOF_USAGE
	Usage:  java_crypto -e <MAILTO> [-I] [-X] [-h]	
	OPTIONS:
	-e send test results to specified email account after test.
	-I Not install any package of framework and test suite.
	-X Not do configure & execution.
	-h help
EOF_USAGE
}

function r_err {
	typeset RESULT=$1
	typeset ERR_MSG=$2
	if (( $RESULT != 0));then
		print "$ERR_MSG"
		exit $RESULT
	fi
}

function copy_test {
	print "Copy the jdk/test to /var/tmp/jdk/test..."
	rm -rf /var/tmp/jdk
	mkdir /var/tmp/jdk
	cp -r /java/re/jdk/9/latest/ws/jdk/test /var/tmp/jdk/test
        cd /var/tmp/jdk || exit 1
        if [[ $(isainfo -n) = amd64 ]]; then
                arc=x64
        else
                arc=$(isainfo -n)
        fi

}	

function java_run {
	if [[ $(isainfo -n) = amd64 ]]; then
		arc=x64
	else
		arc=$(isainfo -n)
	fi

	cd /var/tmp/jdk/test
	ln -s /java/re/jdk/9/latest/binaries/solaris-$arc/bin .
	print "Start test ..."
	gmake jdk_security2 |tee 
	gmake jdk_security3 |tee

}
function process_results {
	mkdir -m 755 -p $SAVE_LOG
	cp -r /var/tmp/jdk/testoutput/jdk_security2 $SAVE_LOG/
	cp -r /var/tmp/jdk/testoutput/jdk_security3 $SAVE_LOG/
	echo "Test results can be found:\n $SAVE_LOG \n" >$SUMMARY
	cat $SAVE_LOG/jdk_security2/Stats.txt >>$SUMMARY
	cat $SAVE_LOG/jdk_security3/Stats.txt >>$SUMMARY	
}

function send_mail {
	if [[ -n $MAILTO ]];then
		echo "Sent mail to $MAILTO"
		SUBJECT="Java crypto Test Result Summary of $(hostname)"
		/usr/bin/mailx -s "$SUBJECT" $MAILTO < $SUMMARY
	fi
}

while getopts "e:hXI" opt; do
	case $opt in
		I)
			NOINSTALL="yes";;
		X)	
			NOEXECUTE="yes";;
		h)
			usage
			exit 0;;
		e)
			MAILTO=$OPTARG;;
		*)	
			usage
			exit 1;;	

	esac
done

if [[ -z "$MAILTO" ]];then 
	usage
	r_err 1 "ERROR: Please set the MAILTO."
else
	MAILTO=$(echo $MAILTO | sed -e 's/,/ /g')
fi

if [[ ! -z "$NOEXECUTE" ]]; then
	exit 0
fi

if [[ -z "$NOINSTALL" ]]; then
	copy_test	
fi


java_run
process_results
send_mail
