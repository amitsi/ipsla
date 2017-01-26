#!/bin/bash

if [[ $( uname -s ) = "SunOS" ]]; then
        GREP="ggrep"
else
        GREP="grep"
fi

trap error ERR
trap cleanup SIGINT SIGTERM EXIT

RED='\033[0;31m'
NC='\033[0m'

default_yml_file="
LinkTrackIP1:10.10.10.100
-switch_host:aquila-ext-43
-switch_username:network-admin
-switch_password:test123
-vrouter_name:test-vr
-network:10.10.10.0
-netmask:255.255.255.0
-gateway:10.10.10.1
-distance:100
-custom_message:This is the link to US DC
LinkTrackIP2:11.11.11.100
-switch_host:aquila-ext-43
-switch_username:network-admin
-switch_password:test123
-vrouter_name:test-vr
-network:11.11.11.0
-netmask:255.255.255.0
-gateway:11.11.11.1
-distance:100
-custom_message:This is the link to Germany DC
email_id:<EMAIL-ID>
email_password:<EMAIL-PASSWORD>
link_down_message:Link is not reachable
link_up_message:Link is back up
sysadmin:<SYSADMIN-EMAIL-ADDRESS>
ping_timer:3
failure_threshold:2
keep_backup_route:false
"

print_help()
{
        printf "  IPSLA Script will monitor connection links for its\n"
        printf "  availability. If primary link is down, it will create\n"
        printf "  backup static link, until primary link comes up again.\n\n"

        printf "  Usage: ipsla [OPTIONS]\n\n"
        printf "  OPTIONS:\n"
        printf "      -f        Read YML file as input. This should contain\n"
        printf "                details of links to track, host from which\n"
        printf "                to track, email settings and other configurations\n"
        printf "      -h        Print this help\n"
}

generate_yml()
{
        choice="n"
        printf "Please provide YML file as an argument : ${RED}${0##*/} -f <filename.yml>${NC}\n\n"
        printf "Do you want to generate sample YML file in /tmp/file.yml\n"
        printf "as a example. ${RED}(y/n):${NC}"
        read choice
        if [ $choice == "y" ]; then
                echo "$default_yml_file" > /tmp/file.yml
                printf "\n#####Sample YML file is created in /tmp/file.yml######\n"
                printf "\n${RED}$default_yml_file${NC}\n\n"
        fi
        exit 0
}

error() {
	log "[ERROR]: The IPSLA script failed while running the command $BASH_COMMAND at line $BASH_LINENO"
	exit 1
}


cleanup() {
	if [ -f $LOCKFILE ]; then
		rm -f "$LOCKFILE"
	fi
	trap - SIGTERM && kill -- -$$
}

vrouter_ping()
{
	cli=$1
	vrouter=$2
	ltip=$3
        $cli vrouter-ping vrouter-name $vrouter host-ip $ltip count 1 | $GREP -E 'Unreachable|unreachable|unknown|not|100% packet loss' | wc -l
}

configure_ssmtp()
{
	email_id=`cat $ymlfile | $GREP 'email_id' | cut -d : -f2`
	email_password=`cat $ymlfile | $GREP 'email_password' | cut -d : -f2`
	mkdir -p /etc/ssmtp/
	touch /etc/ssmtp/ssmtp.conf
	if ! grep -q "##IPSLA EMAIL CONF##" /etc/ssmtp/ssmtp.conf; then
		echo "##IPSLA EMAIL CONF##
AuthUser=$email_id
AuthPass=$email_password
FromLineOverride=YES
mailhub=smtp.gmail.com:587
UseSTARTTLS=YES" >> /etc/ssmtp/ssmtp.conf
	fi
}

send_mail()
{
        subject=$1
        content=$2
	cmsg=$3
ssmtp -C/etc/ssmtp/ssmtp.conf $sysadmin << EOF
To: $sysadmin
From:$email_id
Subject: $subject

$content

$cmsg
EOF
}

LOGFILE="/var/tmp/ipsla.log"
LOCKFILE="/tmp/.ipsla.lock"

log()
{
	if ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
		echo `date +"%b%d.%H.%M.%S:"`"ipsla_notification:$1" >> $LOGFILE
		rm -f "$LOCKFILE"
	fi
}

track_link()
{
	cli=$1
	ltip=$2
	vrouter=$3
	network=$4
	netmask=$5
	gateway=$6
	distance=$7
	cmsg=$8
        ping_failure=0
	while true
        do
                count=`vrouter_ping "$cli" $vrouter $ltip`

		# Check for ping failure
                if [ $count -ne 0 ]; then
                        ping_failure=$((ping_failure+1))
                        if [[ ! $ping_failure > $failure_threshold ]]; then
				log "[$ltip] LinkTrackIP is unreachable"
			fi
			if [ $ping_failure == $failure_threshold ]; then
				log "[$ltip] Notify sysadmin:$sysadmin - LinkTrackIP is unreachable"
				send_mail "IPSLA-Notification: LinkTrackIP $ltip is unreachable from vrouter $vrouter" "$link_down_message" "$cmsg"
				log "[$ltip] Adding backup route for network: $network"
				$cli vrouter-static-route-add vrouter-name $vrouter network $network netmask $netmask gateway-ip $gateway distance $distance
			fi
		else
                        if [[ ! $ping_failure < $failure_threshold ]]; then
				log "[$ltip] Notify sysadmin:$sysadmin - LinkTrackIP is reachable"
				if [ "$keep_backup_route" != "true" ]; then
					log "[$ltip] Removing backup route for network: $network"
					$cli vrouter-static-route-remove vrouter-name $vrouter network $network netmask $netmask gateway-ip $gateway
				fi
				send_mail "IPSLA-Notification: LinkTrackIP $ltip is reachable from vrouter $vrouter" "$link_up_message" "$cmsg"
			fi	
			ping_failure=0
                fi
		sleep $ping_timer
	done
}

if [[ ! $@ =~ ^\-.+ ]]
then
        generate_yml
fi
while getopts ":f:h:" opt; do
        case $opt in
        f)
                if [ ! -f $OPTARG ]; then
                        echo "$OPTARG does not exist !"
                        exit 1
                fi
                ymlfile=$OPTARG
        ;;
        h)
                print_help
                exit 0
        ;;
        \?)
                echo "Invalid option: -$OPTARG" >&2
                print_help
                exit 1
        ;;
        :)
                print_help
                exit 1
        ;;
        esac
done

# Get input details from YML file

ping_timer=`cat $ymlfile | $GREP 'ping_timer' | cut -d : -f2`
failure_threshold=`cat $ymlfile | $GREP 'failure_threshold' | cut -d : -f2`
link_up_message=`cat $ymlfile | $GREP 'link_up_message' | cut -d : -f2`
link_down_message=`cat $ymlfile | $GREP 'link_down_message' | cut -d : -f2`
sysadmin=`cat $ymlfile | $GREP 'sysadmin' | cut -d : -f2`
keep_backup_route=`cat $ymlfile | $GREP 'keep_backup_route' | cut -d : -f2`

links=`cat $ymlfile | grep "LinkTrackIP" | wc -l`

configure_ssmtp

for (( i=1; i<=$links; i++)) do
        linktrackip=`cat $ymlfile | $GREP "^LinkTrackIP$i" | cut -d : -f2`
        switch_host=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-switch_host" | cut -d : -f2`
        switch_username=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-switch_username" | cut -d : -f2`
        switch_password=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-switch_password" | cut -d : -f2`
        vrouter=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-vrouter_name" | cut -d : -f2`
        network=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-network" | cut -d : -f2`
        netmask=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-netmask" | cut -d : -f2`
        gateway=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-gateway" | cut -d : -f2`
        distance=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-distance" | cut -d : -f2`
        cmsg=`cat $ymlfile | $GREP -A 9 "^LinkTrackIP$i" | $GREP "^-custom_message" | cut -d : -f2`
	if [ $switch_host == `hostname` ]; then
		cli="cli --user $switch_username:$switch_password --quiet "
	else
		cli="cli --user $switch_username:$switch_password --quiet --host $switch_host "
	fi

        track_link "$cli" $linktrackip $vrouter $network $netmask $gateway $distance "$cmsg" &
done
wait
