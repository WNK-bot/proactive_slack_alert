#!/bin/bash

function main {
	
	information
	server_stats
	which_stack
	database_services
	php_services
	redis_service
	memcache_service
	elasticsearch_service
	disk_stats
	slack_api

}

function slack_api {
	
	if [[ "$webstack_alert" -eq 1 || "$mariadb_alert" -gt 0 || "$mysql_alert" -gt 0 || "$rs_space_status" == "Critical" || "$rs_inode_status" == 'Critical' || "$bs_space_status" == 'Critical' || "$bs_inode_satus" == 'Critical' || "$php_alert" -gt '0' || "$redis_status" == 'Down' || "$memcache_status" == 'Down' || "$elasticsearch_status" == 'Down' || "$cpu_alert" -gt '0' || "$mem_alert" -gt '0' ]]; then
	
		curl_status=$(curl -s -X POST --data-urlencode "payload={\"channel\": \"#proactive-monitoring\", \"username\": \"webhookbot\", \"blocks\":[{ \"type\":\"section\", \"text\":{ \"type\":\"mrkdwn\", \"text\":\"Server IP: *${PublicIP}* \nServer Name: *${server_name}* \nCPU: *${cpu_status}* \n Memory: *${mem_status}* \n ${webstack_name} : *${webstack_status}* \n ${database_type}: *${database_status}* \n Redis: *${redis_status}* \n Elastic Search: *${elasticsearch_status}* \n Memcache: *${memcache_status}* \n *${php_result}* \n *${storage_result}*\"}},{\"type\":\"divider\"}], \"icon_emoji\":\":rotating_light:\"}" "$slack_webhook")	
		curl_status=$(echo $curl_status | awk -F " " '{print $NF}')
		var_sleep=$(echo $((RANDOM%6)))
	
		while [[ curl_status == ok ]]; do
	
			sleep $var_sleep
			curl_status=$(curl -s -X POST --data-urlencode "payload={\"channel\": \"#proactive-monitoring\", \"username\": \"webhookbot\", \"blocks\":[{ \"type\":\"section\", \"text\":{ \"type\":\"mrkdwn\", \"text\":\"Server IP: *${PublicIP}* \nServer Name: *${server_name}* \nCPU: *${cpu_alert}* \n Memory: *${mem_alert}* \n ${webstack_name} : *${webstack_status}* \n ${database_type}: *${database_status}* \n Redis: *${redis_status}* \n Elastic Search: *${elasticsearch_status}* \n Memcache: *${memcache_status}* \n *${php_result}* \n *${storage_result}*\"}},{\"type\":\"divider\"}], \"icon_emoji\":\":rotating_light:\"}" $slack_webhook)
			curl_status=$(echo $curl_status | awk -F " " '{print $NF}')
		
		done
	
	fi
}

function information {

	PublicIP=$(dig @resolver1.opendns.com myip.opendns.com +short)
	check1=$(echo "$PublicIP" | egrep '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
	check2=$(echo "$PublicIP" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | egrep Y)

	if [[ -z "$check1" ]]; then
		PublicIP='PUBLIC_IP_NOT_FOUND'
	else
		if [[ "$check2" != 'Y' ]]; then
			PublicIP='PUBLIC_IP_NOT_FOUND'
		fi
	fi
}

function which_stack {

	webstack_alert='0'
	webstack_name=$(ls -l /etc/init.d/ | egrep 'nginx|apache2|lsws' | awk '{print $NF}')
	webstack_http=$(netstat -nltp | grep ':80 ' | sort -u | sed 's+: worker++' | awk '{print $NF}' | cut -d '/' -f 2)
	webstack_https=$(netstat -nltp | grep ':443 ' | sort -u | sed 's+: worker++' | awk '{print $NF}' | cut -d '/' -f 2)
	webstack_status=$(systemctl status "$webstack_name" | grep active | awk '{print $2}')
 	[[ $webstack_name == 'lsws' ]] && webstack_name='openlitespeed'
	
if [[ $webstack_status == 'active' ]]; then

	webstack_status='Up'
	[[ -z "$webstack_http" ]] && webstack_status="Only port 80 is down, while $webstack_name is active." && webstack_alert='1'
	[[ -z "$webstack_https" ]] && webstack_status="Only port 443 is down, while $webstack_name is active" && webstack_alert='1'
	[[ -z "$webstack_http" ]] && [[ -z "$webstack_https" ]] && webstack_status="Both ports 80 & 443 are down, while $webstack_name is active." && webstack_alert='1'

else

	webstack_alert='1'
	webstack_status='Down'	

fi
	
}

function database_services {

	database_status='Up'
	mariadb_alert='0'
	mysql_alert='0'
	database_check=$(ls -al /etc/init.d/ | grep -Ei mysql | wc -l)
	[[ $database_check -gt 0 ]] && database_type=$(mysql --version | grep -i  mariadb | wc -l)
	[[ $database_type -gt 0 ]] && database_type="mariadb" || database_type="mysql"

	if [ "$database_type" == "mariadb" ]; then

		database_type="MariaDB"
		mariadb_status=$(systemctl status mysql | grep -Ei active | cut -d: -f2 | awk '{print $1}' | head -1)

		if [ ! "$mariadb_status" == "active" ]; then
			mariadb_alert='1'
		fi
    
	elif [ "$database_type" == "mysql" ]; then

		database_type="MySQL"
		mysql_status=$(systemctl status mysql | grep -Ei active | cut -d: -f2 | awk '{print $1}' | head -1)

		if [ ! "$mysql_status" == "active" ]; then
        	mysql_alert='1'
		fi
	fi

	sum_database=$(($mysql_alert + $mariadb_alert))
	[[ $sum_database -gt 0 ]] && database_status='Down'

}

function disk_stats {

	rs_data=$(df -hT | grep 'ext4' | egrep "/$")
	rs_name=$(echo "$rs_data" | awk '{print $1}' | sed 's+/dev/++g')
	rs_total=$(echo "$rs_data" | awk '{print $3}')
	rs_used=$(echo "$rs_data" | awk '{print $4}')
	rs_avail=$(echo "$rs_data" | awk '{print $5}')
	rs_perc=$(echo "$rs_data" | awk '{print $6}')
	rs_perc_check=$(echo $rs_perc | awk -F "." '{print $1}' | sed "s+%++g")

	rs_idata=$(df -ihT | grep 'ext4' | egrep "/$")
	rs_iname=$(echo "$rs_idata" | awk '{print $1}' | sed 's+/dev/++g')
	rs_itotal=$(echo "$rs_idata" | awk '{print $3}')
	rs_iused=$(echo "$rs_idata" | awk '{print $4}')
	rs_iavail=$(echo "$rs_idata" | awk '{print $5}')
	rs_iperc=$(echo "$rs_idata" | awk '{print $6}')
	rs_iperc_check=$(echo "$rs_iperc" | awk -F "." '{print $1}' | sed "s+%++g")

	bs_data=$(df -hT | grep 'ext4' | egrep "/mnt/user_data")
	bs_name=$(echo "$bs_data" | awk '{print $1}' | sed 's+/dev/++g')
	bs_total=$(echo "$bs_data" | awk '{print $3}')
	bs_used=$(echo "$bs_data" | awk '{print $4}')
	bs_avail=$(echo "$bs_data" | awk '{print $5}')
	bs_perc=$(echo "$bs_data" | awk '{print $6}')
	bs_perc_check=$(echo $bs_perc | awk -F "." '{print $1}' | sed "s+%++g")

	bs_idata=$(df -ihT | grep 'ext4' | egrep "/mnt/user_data")
	bs_iname=$(echo "$bs_idata" | awk '{print $1}' | sed 's+/dev/++g')
	bs_itotal=$(echo "$bs_idata" | awk '{print $3}')
	bs_iused=$(echo "$bs_idata" | awk '{print $4}')
	bs_iavail=$(echo "$bs_idata" | awk '{print $5}')
	bs_iperc=$(echo "$bs_idata" | awk '{print $6}')
	bs_iperc_check=$(echo $bs_iperc | awk -F "." '{print $1}' | sed "s+%++g")

	if [[ $rs_perc_check -ge $rs_space_threshold ]]; then
		rs_space_status="Critical"
	else
		rs_space_status="Good"
	fi

	if [[ $rs_iperc_check -ge $rs_inode_threshold ]]; then
	    rs_inode_status="Critical"
	else
		rs_inode_status="Good"
	fi

	if [[ $bs_perc_check -ge $bs_space_threshold ]]; then
		bs_space_status="Critical"
	else
		bs_space_status="Good"
	fi

	if [[ $bs_iperc_check -ge $bs_inode_threshold ]]; then
		bs_inode_status="Critical"
	else
		bs_inode_status="Good"
	fi

	storage_result=$(echo "Root Disk: "$rs_space_status" || Root Inode: "$rs_inode_status" || Storage Space: "$bs_space_status" || Storage Inode: "$bs_inode_status"")

}

function php_services {

	php_alert='0'
	php_array=($(ls -l /etc/init.d/ | grep -E php | awk '{print $9}'))
	length_php_array="${#php_array[@]}"

	for (( i=0; i<$length_php_array; i++ )) do

	    php_version=$(echo "${php_array[$i]}" | awk -F "-" '{print $1}' | sed 's/php//' )
	    php_status=$(systemctl status "${php_array[$i]}" | grep -i active | head -1 | awk '{print $2}')

	    if [ "$php_status" == "active" ]; then
        	[ $i == 0 ] && php_var1=$(echo "PHP-FPM ${php_version}: Up") || php_result=$(echo "$php_var1 ||" "PHP-FPM ${php_version}: Up")

	    else
            [ $i == 0 ] && php_var1=$(echo "PHP-FPM ${php_version}: Down") || php_result=$(echo "$php_var1 ||" "PHP-FPM ${php_version}: Down")
			((php_alert++))
	    fi
    
	done
	
	[ "$i" == 1 ] && php_result=$(echo $php_var1) 

}

function redis_service {

	redis_status='Up'
	redis_check=$(ls -al /etc/init.d/ | grep -Ei redis | awk '{print $9}')

    if [[ -n $redis_check ]]; then

	    redis_status=$(systemctl status "$redis_check" | grep -Ei active | awk -F " " '{print $2}')

        if [[ ! $redis_status == active ]]; then
            redis_status='Down'
        fi
        
	else
	    redis_status='Null'
	fi

}

function memcache_service {

	memcache_status='Up'
	memcache_check=$(ls -al /etc/init.d/ | grep -Ei memcache | awk '{print $9}')

    if [[ -n $memcache_check ]]; then

        memcache_status=$(systemctl status "$memcached_check" | grep -Ei active | awk -F " " '{print $2}')

        if [[ ! $memcache_status == active ]]; then
            memcache_status='Down'
        fi
	
	else
		memcache_status='Null'
	fi

}

function elasticsearch_service {

	elasticsearch_status='Up'
	elasticsearch_check=$(ls -al /etc/init.d/ | grep -Ei elasticsearch | awk '{print $9}')

    if [[ -n $elasticsearch_check ]]; then

        elasticsearch_status=$(systemctl status "$elasticsearch_check" | grep -Ei active | awk -F " " '{print $2}')

        if [[ ! $elasticsearch_status == active ]]; then
	        elasticsearch_status='Down'
        fi
		
	else
		elasticsearch_status='Null'
    fi

}

function server_stats {

    consecutive_high=0
    for ((i=0; i<3; i++)); do
        
        current_load=$(top -bn1 | awk '/Cpu\(s\)/{print $2 + $4 + $6}' | awk -F. '{print $1}')
  
        if [ "$current_load" -gt "$cpu_threshold" ]; then
        
            consecutive_high=$((consecutive_high + 1))
		    
        else
        
            consecutive_high=0
		    break
    
        fi

        [[ $consecutive_high -eq 3 ]] || sleep 5
    
    done

    if [ "$consecutive_high" -eq 3 ]; then
        
        no_of_core=$(nproc)
	    core_threshold=$(echo "scale=2; $no_of_core * $cpu_threshold / 100" | bc)
        avg_load_5min=$(uptime | awk '{print $11}' | sed "s:,::g")

    	if (( $(awk 'BEGIN {print ("'"$avg_load_5min"'" > "'"$core_threshold"'")}') )); then       

            cpu_alert='1' && cpu_status='Critical'

        else
    
            cpu_alert='0' 
            cpu_status='Good'
    
        fi
    
    else
  
        cpu_alert='0' 
        cpu_status='Good'
    
    fi

	mem_alert="0"
    mem_status='Good'
	mem_free_data=`free -m | grep Mem`
	mem_current=`echo $mem_free_data | cut -f3 -d' '`
	mem_total=`echo $mem_free_data | cut -f2 -d' '`
	mem_usage=$(echo "scale = 2; $mem_current/$mem_total*100" | bc | awk -F "." '{print $1}')

	if [ "$mem_usage" -ge "$mem_threshold" ]; then

		mem_alert="1"
    mem_status='Critical'

	fi

}

while getopts ":c:m:r:i:b:I:s:w:" opt; do
	case $opt in
    c) cpu_threshold="$OPTARG"
    ;;
		m) mem_threshold="$OPTARG"
		;;
    r) rs_space_threshold="$OPTARG"
    ;;
		i) rs_inode_threshold="$OPTARG"
		;;
		b) bs_space_threshold="$OPTARG"
    ;;
    I) bs_inode_threshold="$OPTARG"
    ;;
		s) server_name="$OPTARG"
		;;
    w) slack_webhook="$OPTARG"
    ;;
  esac
done

main "$@"
