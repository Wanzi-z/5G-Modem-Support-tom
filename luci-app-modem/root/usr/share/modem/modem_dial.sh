#!/bin/sh
source /lib/functions.sh
#运行目录
MODEM_RUNDIR="/var/run/modem"
#脚本目录
SCRIPT_DIR="/usr/share/modem"
#导入组件工具
source "${SCRIPT_DIR}/modem_debug.sh"
get_driver()
{
	for i in $(find $modem_path -name driver);do
		lsfile=$(ls -l $i)
		type=${lsfile:0:1}
		if [ "$type" == "l" ];then
			link=$(basename $(ls -l $i | awk '{print $11}'))
			case $link in
				"qmi_wwan"*) 
					mode="qmi"
					break
				;;
				"cdc_mbim")
					mode="mbim"
					break
					;;
				"cdc_ncm")
					mode="ncm"
					break
					;;
				"cdc_ether")
					mode="ecm"
					break
					;;
				"rndis_host")
					mode="rndis"
					break
					;;
				*)
					if [ -z "$mode" ]; then
						mode="unknown"
					fi
				;;
			esac
		fi
	done
    echo $mode
}
config_load modem
modem_config=$1
log_path="${MODEM_RUNDIR}/${modem_config}_dial.cache"
config_get enable_dial $modem_config enable_dial
config_get modem_path $modem_config path
config_get modem_dial $modem_config enable_dial
config_get dial_tool $modem_config dial_tool
config_get pdp_type $modem_config pdp_type
config_get network_bridge $modem_config network_bridge
config_get apn $modem_config apn
config_get username $modem_config username
config_get password $modem_config password
config_get auth $modem_config auth
config_get at_port $modem_config at_port
config_get manufacturer $modem_config manufacturer
config_get platform $modem_config platform
config_get define_connect $modem_config define_connect
global_dial=$(uci -q get modem.@global[0].enable_dial)
[ "$2" == "hang" ] && enable_dial=0
if [ "$global_dial" == 0 ];then
    enable_dial=0
fi
modem_netcard=$(ls $(find $modem_path -name net |tail -1) | awk -F'/' '{print $NF}')
interface_name=wwan_5g_$(echo $modem_config | grep -oE "[0-9]+")
interface6_name=wwan6_5g_$(echo $modem_config | grep -oE "[0-9]+")
ethernet_5g=$(uci -q get modem.global.ethernet)
driver=$(get_driver)
dial_log "modem_path=$modem_path,driver=$driver,interface=$interface_name,at_port=$at_port" "$log_path"

check_ip()
{
    case $manufacturer in
            "quectel")
                case $platform in
                    "qualcomm")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "unisoc")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "lte")
                        if [ "$define_connect" = "3" ];then
                            check_ip_command="AT+CGPADDR=3"
                        else
                            check_ip_command="AT+CGPADDR=1"
                        fi
                        ;;
                    
                esac
                ;;
            "fibocom")
                case $platform in
                    "qualcomm")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "unisoc")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "lte")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "mediatek")
                        check_ip_command="AT+CGPADDR=3"
                        stric=1
                        ;;
                esac
                ;;
        esac
        ipaddr=$(at "$at_port" "$check_ip_command" |grep +CGPADDR:)
        if [ -n "$ipaddr" ];then
            ipv6=$(echo $ipaddr | grep -oE "\b([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\b")
            ipv4=$(echo $ipaddr | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
            disallow_ipv4="0.0.0.0"
            #remove the disallow ip
            if [ "$ipv4" == *"$disallow_ipv4"* ];then
                ipv4=""
            fi
            connection_status=0
            if [ -n "$ipv4" ];then
                connection_status=1
            fi
            if [ -n "$ipv6" ];then
                connection_status=2
            fi
            if [ -n "$ipv4" ] && [ -n "$ipv6" ];then
                connection_status=3
            fi
            dial_log "current ip [$ipv6],[$ipv4],connection_status=$connection_status" "$log_path"
        else
            connection_status="-1"
            dial_log "at port response unexpected $ipaddr" "$log_path"
        fi
}

set_if()
{
    #check if exist
    interface=$(uci -q get network.$interface_name)
    if [ -z "$interface" ];then
        uci set network.${interface_name}=interface
        uci set network.${interface_name}.proto='dhcp'
        uci set network.${interface_name}.defaultroute='1'
        uci set network.${interface_name}.peerdns='0'
        uci set network.${interface_name}.metric='10'
        uci add_list network.${interface_name}.dns='114.114.114.114'
        uci add_list network.${interface_name}.dns='119.29.29.29'
        local num=$(uci show firewall | grep "name='wan'" | wc -l)
        local wwan_num=$(uci -q get firewall.@zone[$num].network | grep -w "${interface_name}" | wc -l)
        if [ "$wwan_num" = "0" ]; then
            uci add_list firewall.@zone[$num].network="${interface_name}"
        fi

        #set ipv6
        #if pdptype contain 6
        if [ -n "$(echo $pdp_type | grep "6")" ];then
            uci set network.lan.ipv6='1'
            uci set network.lan.ip6assign='64'
            uci set network.lan.ip6class="${interface6_name}"
            uci set network.${interface6_name}='interface'
            uci set network.${interface6_name}.proto='dhcpv6'
            uci set network.${interface6_name}.extendprefix='1'
            uci set network.${interface6_name}.ifname="@${interface_name}"
            uci set network.${interface6_name}.device="@${interface_name}"
            uci set network.${interface6_name}.metric='10'
            local wwan6_num=$(uci -q get firewall.@zone[$num].network | grep -w "${interface6_name}" | wc -l)
            if [ "$wwan6_num" = "0" ]; then
                uci add_list firewall.@zone[$num].network="${interface6_name}"
            fi
        fi


        
        uci commit network
        uci commit firewall
        ifup ${interface_name}
        dial_log "create interface $interface_name" "$log_path"

    fi

    set_modem_netcard=$modem_netcard
    if [ -z "$set_modem_netcard" ];then
        dial_log "no netcard found" "$log_path"
    fi
    ethernet_check=$(handle_5gethernet)
    if [ -n "$ethernet_check" ];then
        set_modem_netcard=$ethernet_5g
    fi
    #set led
    uci set system.led_wwan.dev="${set_modem_netcard}"
    uci commit system
    origin_netcard=$(uci -q get network.$interface_name.ifname)
    origin_device=$(uci -q get network.$interface_name.device)
    if [ "$origin_netcard" == "$set_modem_netcard" ] && [ "$origin_device" == "$set_modem_netcard" ];then
        dial_log "interface $interface_name already set to $set_modem_netcard" "$log_path"
    else
        uci set network.${interface_name}.ifname="${set_modem_netcard}"
        uci set network.${interface_name}.device="${set_modem_netcard}"
        
        uci commit network
        ifup ${interface_name}
        dial_log "set interface $interface_name to $modem_netcard" "$log_path"
    fi
}

flush_if()
{
    uci delete network.${interface_name}
    uci delete network.${interface6_name}
    uci commit network
    dial_log "delete interface $interface_name" "$log_path"

}

dial(){
    set_if
    dial_log "dialing $modem_path driver $driver" "$log_path"
    case $driver in
        "qmi")
            qmi_dial
            ;;
        "mbim")
            mbim_dial
            ;;
        "ncm")
            at_dial_monitor
            ;;
        "ecm")
            at_dial_monitor
            ;;
        "rndis")
            at_dial_monitor
            ;;
        *)
            mbim_dial
            ;;
    esac
}

wwan_hang()
{
    #kill quectel-CM
    killall quectel-CM
}


ecm_hang()
{
    if [ "$manufacturer" = "quectel" ]; then
		at_command="AT+QNETDEVCTL=1,2,1"
	elif [ "$manufacturer" = "fibocom" ]; then
		#联发科平台（广和通FM350-GL）
		if [ "$platform" = "mediatek" ]; then
			at_command="AT+CGACT=0,3"
		else
			at_command="AT+GTRNDIS=0,1"
		fi
	elif [ "$manufacturer" = "meig" ]; then
		at_command="AT$QCRMCALL=0,1,1,2,1"
	else
		at_command='ATI'
	fi

	tmp=$(at "${at_port}" "${at_command}")
}

fake_run()
{
    while true; do
        sleep 5
    done
}

hang()
{
    logger -t modem "hang up $modem_path driver $driver"
    case $driver in
        "ncm")
            ecm_hang
            ;;
        "ecm")
            ecm_hang
            ;;
        "rndis")
            ecm_hang
            ;;
        "qmi")
            wwan_hang
            ;;
        "mbim")
            wwan_hang
            ;;
    esac
    flush_if
    #fake_run
}

mbim_dial(){
    modem_path=$1
    modem_dial=$2
    if [ -z "$apn" ];then
        apn="auto"
    fi
    qmi_dial
}

qmi_dial()
{
    cmd_line="quectel-CM"

	case $pdp_type in
		"ip") cmd_line="$cmd_line -4" ;;
		"ipv6") cmd_line="$cmd_line -6" ;;
		"ipv4v6") cmd_line="$cmd_line -4 -6" ;;
		*) cmd_line="$cmd_line -4 -6" ;;
	esac

	if [ "$network_bridge" = "1" ]; then
		cmd_line="$cmd_line -b"
	fi
	if [ -n "$apn" ]; then
		cmd_line="$cmd_line -s $apn"
	fi
	if [ -n "$username" ]; then
		cmd_line="$cmd_line $username"
	fi
	if [ -n "$password" ]; then
		cmd_line="$cmd_line $password"
	fi
	if [ "$auth" != "none" ]; then
		cmd_line="$cmd_line $auth"
	fi
	if [ -n "$modem_netcard" ]; then
		cmd_line="$cmd_line -i $modem_netcard"
	fi
    
    cmd_line="$cmd_line -f $log_path"
    $cmd_line
    
    
}

at_dial()
{

    apn=$(uci -q get modem.$modem_config.apn)
    pdp_type=$(uci -q get modem.$modem_config.pdp_type)
    if [ -z "$apn" ];then
        apn="auto"
    fi
    if [ -z "$pdp_type" ];then
        pdp_type="IP"
    fi
    local at_command='AT+COPS=0,0'
	tmp=$(at "${at_port}" "${at_command}")
    pdp_type=$(echo $pdp_type | tr 'a-z' 'A-Z')
    case $manufacturer in
        "quectel")
            case $platform in
                "qualcomm")
                    at_command="AT+QNETDEVCTL=1,3,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "unisoc")
                    at_command="AT+QNETDEVCTL=1,3,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "lte")
                    if [ "$define_connect" = "3" ];then
                        at_command="AT+QNETDEVCTL=3,3,1"
                        cgdcont_command="AT+CGDCONT=3,\"$pdp_type\",\"$apn\""
                    else
                        at_command="AT+QNETDEVCTL=1,3,1"
                        cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    fi
                    ;;
                *)
                    at_command="AT+QNETDEVCTL=1,3,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
        "fibocom")
            case $platform in
                "qualcomm")
                    at_command="AT+GTRNDIS=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "unisoc")
                    at_command="AT+GTRNDIS=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "lte")
                    at_command="AT+GTRNDIS=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "mediatek")
                    at_command="AT+CGACT=1,3"
                    cgdcont_command="AT+CGDCONT=3,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
            
    esac
    dial_log "dialing vendor:$manufacturer;platform:$platform; $cgdcont_command ; $at_command" "$log_path"
    at "${at_port}" "${cgdcont_command}"
    at "$at_port" "$at_command"
}

ip_change_fm350()
{
    dial_log "ip_change_fm350" "$log_path"
    at_command="AT+CGPADDR=3"
    local ipv4_config=$(at ${at_port} ${at_command} | cut -d, -f2 | grep -oE '[0-9]+.[0-9]+.[0-9]+.[0-9]+')
    local public_dns1_ipv4="223.5.5.5"
    local public_dns2_ipv4="119.29.29.29"
    local public_dns1_ipv6="2400:3200::1"
    local public_dns2_ipv6="2402:4e00::"
    at_command="AT+GTDNS=3" | grep "+GTDNS: "| grep -E '[0-9]+.[0-9]+.[0-9]+.[0-9]+' | sed -n '1p'
    local ipv4_dns1=$(echo "${response}" | awk -F'"' '{print $2}' | awk -F',' '{print $1}')
    [ -z "$ipv4_dns1" ] && {
        ipv4_dns1="${public_dns1_ipv4}"
    }

    local ipv4_dns2=$(echo "${response}" | awk -F'"' '{print $4}' | awk -F',' '{print $1}')
    [ -z "$ipv4_dns2" ] && {
        ipv4_dns2="${public_dns2_ipv4}"
    }

    local ipv6_dns1=$(echo "${response}" | awk -F'"' '{print $2}' | awk -F',' '{print $2}')
    [ -z "$ipv6_dns1" ] && {
        ipv6_dns1="${public_dns1_ipv6}"
    }

    local ipv6_dns2=$(echo "${response}" | awk -F'"' '{print $4}' | awk -F',' '{print $2}')
    [ -z "$ipv6_dns2" ] && {
        ipv6_dns2="${public_dns2_ipv6}"
    }
    uci_ipv4=$(uci -q get network.$interface_name.ipaddr)
    
    uci set network.${interface_name}.proto='static'
    uci set network.${interface_name}.ipaddr="${ipv4_config}"
    uci set network.${interface_name}.netmask='255.255.255.0'
    uci set network.${interface_name}.gateway="${ipv4_config%.*}.1"
    uci set network.${interface_name}.peerdns='0'
    uci -q del network.${interface_name}.dns
    uci add_list network.${interface_name}.dns="${ipv4_dns1}"
    uci add_list network.${interface_name}.dns="${ipv4_dns2}"
    uci commit network
    ifdown ${interface_name}
    ifup ${interface_name}
    dial_log "set interface $interface_name to $ipv4_config" "$log_path"

}

handle_5gethernet()
{
    case "$driver" in
        "ncm"|\
        "ecm"|\
        "rndis")
            case "$manufacturer" in
                "quectel")
                    case "$platform" in
                        "unisoc")
                            check_ethernet_cmd="AT+QCFG=\"ethernet\""
                            time=0
                            while [ $time -lt 5 ]; do
                                result=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $check_ethernet_cmd | grep "+QCFG:")
                                if [ -n "$result" ]; then
                                    if [ -n "$(echo $result | grep "ethernet\",1")" ]; then
                                        echo "1"
                                        dial_log "5G Ethernet mode is enabled" "$log_path"
                                        break
                                    fi
                                fi
                                sleep 5
                                time=$((time+1))
                            done
                        ;;
                    esac
                    ;;
            esac
        ;;
    esac
}


handle_ip_change()
{
    export ipv4
    export ipv6
    export connection_status
    dial_log "ip changed from $ipv6_cache,$ipv4_cache to $ipv6,$ipv4" "$log_path"
    case $manufacturer in
        "fibocom")
            case $platform in
                "mediatek")
                    ip_change_fm350
                    ;;
            esac
            ;;
    esac
}

check_logfile_line()
{
    local line=$(wc -l $log_path | awk '{print $1}')
    if [ $line -gt 300 ];then
        echo "" > $log_path
        dial_log "log file line is over 300,clear it" "$log_path"
    fi
}

unexpected_response_count=0
at_dial_monitor()
{
    check_ip
    at_dial
    ipv4_cache=$ipv4
    while true; do
        check_ip
        if [ $connection_status -eq 0 ];then
            at_dial
            sleep 5
        elif [ $connection_status -eq -1 ];then
            unexpected_response_count=$((unexpected_response_count+1))
            if [ $unexpected_response_count -gt 3 ];then
                at_dial
                unexpected_response_count=0
            fi
            sleep 10
        else
        #检测ipv4是否变化
            sleep 15
            if [ "$ipv4" != "$ipv4_cache" ];then
                handle_ip_change
                ipv6_cache=$ipv6
                ipv4_cache=$ipv4
            fi
        fi
        check_logfile_line
    done
    
}

case "$enable_dial" in
    "0")
        hang;;
    "1")
        dial;;
esac
