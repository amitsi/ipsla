#!/bin/bash

function error() {
  echo -e "\e[0;33mERROR: The IPSLA script failed while running the command $BASH_COMMAND at line $BASH_LINENO.\e[0m" >&2
  exit 1
}
trap error ERR

ymlfile=$2

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

help="
IPSLA Script will monitor connection links for its availability. If primary link is down it will create backup static link until primary link comes up.


${RED}USAGE: bash ipsla.sh [-h/-help] [-yml] ${NC}

   -h or -help:
       Display brief usage message.

   -yml:
       reads yml file as input. yml file has host1 and host2 details, email account details etc. Please check below exmaple of yml file.

${RED}How to RUN:${NC}

   bash ipsla.sh -yml filename.yml

${RED}=> Contents of filename.yml:${NC}
$default_yml_file

"
ping_timer=`cat $ymlfile | grep 'ping_timer' | cut -d : -f2`
allowed_failure=`cat $ymlfile | grep 'allowed_failure' | cut -d : -f2`
emailContent1=`cat $ymlfile | grep 'emailContent1' | cut -d : -f2`
emailContent2=`cat $ymlfile | grep 'emailContent2' | cut -d : -f2`
sysadmin=`cat $ymlfile | grep 'sysadmin' | cut -d : -f2`
switch_host=`cat $ymlfile | grep 'switch_host' | cut -d : -f2`
switch_username=`cat $ymlfile | grep 'switch_username' | cut -d : -f2`
switch_password=`cat $ymlfile | grep 'switch_password' | cut -d : -f2`

links=`cat $ymlfile | grep 'no_of_links' | cut -d : -f2`

i=1

hosts=()
vrouters=()
networks=()
netmasks=()
gateways=()

for((i=1;i<=$links;i++))
do
  hostname=`cat $ymlfile | grep "LinkTrackIP$i" | cut -d : -f2`
  vrouter=`cat $ymlfile | grep -A 4 "LinkTrackIP$i" | grep "vrouter-name" | cut -d : -f2`
  network=`cat $ymlfile | grep -A 4 "LinkTrackIP$i" | grep "network" | cut -d : -f2`
  netmask=`cat $ymlfile | grep -A 4 "LinkTrackIP$i" | grep "netmask" | cut -d : -f2`
  gateway=`cat $ymlfile | grep -A 4 "LinkTrackIP$i" | grep "gateway" | cut -d : -f2`
  hosts+=($hostname)
  vrouters+=($vrouter)
  networks+=($network)
  netmasks+=($netmask)
  gateways+=($gateway) 
done
distance=`cat $ymlfile | grep 'distance' | cut -d : -f2`


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

linux_ping_host()
{
  index=$1
  ping_failure=0
  reset=0
  while [ "$ping_failure" -ne "$allowed_failure" ]; 
  do
    index_for_old_link_check=$index
    echo "Pinging host - ${hosts[$index]}"
    count=`cli --user $switch_username:$switch_password --quiet --host $switch_host vrouter-ping vrouter-name ${vrouters[$index]} host-ip ${hosts[$index]} count 1 | grep -E 'Unreachable|unreachable|unknown|not' | wc -l`
    if ! [ $count == 0 ];
    then   
      ping_failure=$((ping_failure+1))
      echo "Host is unrechable:${hosts[$index]}" 
    fi
    for((;$index_for_old_link_check>0;))
    do
      index_for_old_link_check=$((index_for_old_link_check-1))
      count=`cli --user $switch_username:$switch_password --quiet --host $switch_host vrouter-ping vrouter-name ${vrouters[$index_for_old_link_check]} host-ip ${hosts[$index_for_old_link_check]} count 1 | grep -E 'Unreachable|unreachable|unknown|not' | wc -l`

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

install_ssmtp()
{
  sudo apt-get -y -qq update
  sudo apt-get -y -qq autoremove sendmail
  sudo apt-get -y -qq install ssmtp
  sudo apt-get -y -qq install mailutils
  emailid=`cat $ymlfile | grep 'emailId' | cut -d : -f2`
  emailPassword=`cat $ymlfile | grep 'emailPassword' | cut -d : -f2`
  count=`cat /etc/ssmtp/ssmtp.conf | grep '##EMAIL CONF##' | wc -l`
  if [ $count == "0" ];
  then
  echo "##EMAIL CONF##
AuthUser=$emailid
AuthPass=$emailPassword
FromLineOverride=YES
mailhub=smtp.gmail.com:587
UseSTARTTLS=YES" >> /etc/ssmtp/ssmtp.conf
  fi
}


###Script Starts here###
if [ "$1" = '-h' ] || [ "$1" = '-help' ]; then
  echo -e "\n\e[0;31m[IP SLA] \e[0m"
  printf "$help"
  exit 0
fi

choice="n"

if ! [[ "$@" == *"-yml"* ]]
then
  printf "\nScript requires .yml file as argument. Please provide yml file as an argument : ${RED}bash ${0##*/} -yml filename.yml${NC}\n\n"
  printf "Shall I generate sample yml file in /tmp/file.yml as a exmaple. ${RED}(y/n):${NC}"
  read choice
  if [ $choice == "y" ];
  then
    echo "$default_yml_file" > /tmp/file.yml
    printf "\n#####Sample yml file is created in /tmp/file.conf with following contents######\n"
    printf "\n${RED}$default_yml_file${NC}\n\n"
  fi
  exit 0
fi


#install_ssmtp

i=1
for((;i<=$links;i++))
do
  index=$(($i-1))
  linux_ping_host $index
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
