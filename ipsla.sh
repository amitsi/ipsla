#!/bin/bash

if [[ $( uname -s ) = "SunOS" ]]; then
	GREP="ggrep"
else
	GREP="grep"
fi

function error() {
  echo -e "\e[0;33mERROR: The IPSLA script failed while running the command $BASH_COMMAND at line $BASH_LINENO.\e[0m" >&2
  exit 1
}
trap error ERR

RED='\033[0;31m'
NC='\033[0m'

default_yml_file="ping-type:vrouter
no_of_links:3
switch_host:auto-spine1
switch_username:network-admin
switch_password:test123
LinkTrackIP1:172.168.0.2
-vrouter-name:o-spine1-vrouter
-network:172.168.0.0
-netmask:255.255.255.252
-gateway:172.168.0.1
LinkTrackIP2:172.168.0.10
-vrouter-name:o-spine1-vrouter
-network:172.168.0.8
-netmask:255.255.255.252
-gateway:172.168.0.9
LinkTrackIP3:172.168.0.6
-vrouter-name:o-spine1-vrouter
-network:172.168.0.4
-netmask:255.255.255.252
-gateway:172.168.0.5
distance:100
emailId:testipsla@gmail.com
emailPassword:testipsla123
emailContent1:Link is Down with for Address
emailContent2:Rolling back. Link is up for Address
sysadmin:sandip.divekar@calsoftinc.com
ping_timer:3
allowed_failure:2
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
allowed_failure=`cat $ymlfile | $GREP 'allowed_failure' | cut -d : -f2`
emailContent1=`cat $ymlfile | $GREP 'emailContent1' | cut -d : -f2`
emailContent2=`cat $ymlfile | $GREP 'emailContent2' | cut -d : -f2`
sysadmin=`cat $ymlfile | $GREP 'sysadmin' | cut -d : -f2`
switch_host=`cat $ymlfile | $GREP 'switch_host' | cut -d : -f2`
switch_username=`cat $ymlfile | $GREP 'switch_username' | cut -d : -f2`
switch_password=`cat $ymlfile | $GREP 'switch_password' | cut -d : -f2`

links=`cat $ymlfile | $GREP 'no_of_links' | cut -d : -f2`

i=1

hosts=()
vrouters=()
networks=()
netmasks=()
gateways=()

for((i=1;i<=$links;i++))
do
  hostname=`cat $ymlfile | $GREP "LinkTrackIP$i" | cut -d : -f2`
  vrouter=`cat $ymlfile | $GREP -A 4 "LinkTrackIP$i" | $GREP "vrouter-name" | cut -d : -f2`
  network=`cat $ymlfile | $GREP -A 4 "LinkTrackIP$i" | $GREP "network" | cut -d : -f2`
  netmask=`cat $ymlfile | $GREP -A 4 "LinkTrackIP$i" | $GREP "netmask" | cut -d : -f2`
  gateway=`cat $ymlfile | $GREP -A 4 "LinkTrackIP$i" | $GREP "gateway" | cut -d : -f2`
  hosts+=($hostname)
  vrouters+=($vrouter)
  networks+=($network)
  netmasks+=($netmask)
  gateways+=($gateway) 
done
distance=`cat $ymlfile | $GREP 'distance' | cut -d : -f2`


create_static_route()
{
  echo "Creating static route"
  index=$1
  cli --user $switch_username:$switch_password --quiet --host $switch_host vrouter-static-route-add vrouter-name ${vrouters[$index]} network ${networks[$index]} netmask ${netmasks[$index]} gateway-ip ${gateways[$index]} distance $distance
  echo "Created static route for network:${networks[$index]}"
}

delete_static_route()
{
  index=$1
  echo "Deleting static route for network: ${networks[$index]}"
  cli --user $switch_username:$switch_password --quiet --host $switch_host vrouter-static-route-remove vrouter-name ${vrouters[$index]} network ${networks[$index]} netmask ${netmasks[$index]} gateway-ip ${gateways[$index]}
}

stop_exit=0
reset=5

ping_host()
{
  index=$1
  ping_failure=0
  reset=0
  while [ "$ping_failure" -ne "$allowed_failure" ];
  do
    index_for_old_link_check=$index
    echo "Pinging host - ${hosts[$index]}"
    count=`cli --user $switch_username:$switch_password --quiet --host $switch_host vrouter-ping vrouter-name ${vrouters[$index]} host-ip ${hosts[$index]} count 1 | $GREP -E 'Unreachable|unreachable|unknown|not' | wc -l`
    if ! [ $count == 0 ];
    then
      ping_failure=$((ping_failure+1))
      echo "Host is unrechable:${hosts[$index]}"
    fi
    for((;$index_for_old_link_check>0;))
    do
      index_for_old_link_check=$((index_for_old_link_check-1))
      count=`cli --user $switch_username:$switch_password --quiet --host $switch_host vrouter-ping vrouter-name ${vrouters[$index_for_old_link_check]} host-ip ${hosts[$index_for_old_link_check]} count 1 | $GREP -E 'Unreachable|unreachable|unknown|not' | wc -l`

      if [ $count == 0 ];
      then
        diff=`expr $index - $index_for_old_link_check`
        j=$index
        for ((;$diff!=0;diff--))
        do
          delete_static_route $j
          j=$((j-1))
        done
        stop_exit=$index_for_old_link_check
        reset=1
        echo "$emailContent2 : ${hosts[$index_for_old_link_check]}" | mail -s "Link ${hosts[$index_for_old_link_check]} is down" $sysadmin
        return 0
      fi

    done

    echo "Sleeping for 3 seconds"
    sleep $ping_timer
  done
  echo "Host ${hosts[$index]} is down. Sending Email"
  echo "$emailContent1 : ${hosts[$index]}" | mail -s "Link ${hosts[$index]} is down" $sysadmin
  stop_exit=$index
  reset=0
}

#install_ssmtp

install_ssmtp()
{
  sudo apt-get -y -qq update
  sudo apt-get -y -qq autoremove sendmail
  sudo apt-get -y -qq install ssmtp
  sudo apt-get -y -qq install mailutils
  emailid=`cat $ymlfile | $GREP 'emailId' | cut -d : -f2`
  emailPassword=`cat $ymlfile | $GREP 'emailPassword' | cut -d : -f2`
  count=`cat /etc/ssmtp/ssmtp.conf | $GREP '##EMAIL CONF##' | wc -l`
  if [ $count == "0" ]; then
  echo "##EMAIL CONF##
AuthUser=$emailid
AuthPass=$emailPassword
FromLineOverride=YES
mailhub=smtp.gmail.com:587
UseSTARTTLS=YES" >> /etc/ssmtp/ssmtp.conf
  fi
}

i=1
for((;i<=$links;i++))
do
  index=$(($i-1))
  ping_host $index
  temp=$stop_exit
  if [ $reset == 1  ];
  then
    i=$temp
  fi

  if [ $i == $links ];
  then
    echo "All links are down exiting from Script"
    exit 0
  else
    if [ $reset != 1 ];
    then
      j=$(($temp+1))
      create_static_route $j
    fi
  fi

done

