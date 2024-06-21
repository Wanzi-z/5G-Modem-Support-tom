#!/bin/sh
source /usr/share/libubox/jshn.sh
method=$1
config_section=$2
at_port=$(uci get modem.$config_section.at_port)
vendor=$(uci get modem.$config_section.manufacturer)
platform=$(uci get modem.$config_section.platform)
define_connect=$(uci get modem.$config_section.define_connect)
[ -z "$define_connect" ] && {
    define_connect="1"
}



case $vendor in
    "quectel")
        . /usr/share/modem/quectel.sh
        ;;
    "fibocom")
        . /usr/share/modem/fibocom.sh
        ;;
    *)
        . /usr/share/modem/generic.sh
        ;;
esac

try_cache() {
    cache_timeout=$1
    cache_file=$2
    function_name=$3
    current_time=$(date +%s)
    file_time=$(stat -t $cache_file | awk '{print $14}')
    if [ ! -f $cache_file ] || [ $(($current_time - $file_time)) -gt $cache_timeout ]; then
        touch $cache_file
        json_add_array modem_info
        $function_name
        json_close_array
        json_dump > $cache_file
        return 1
    else
        cat $cache_file
        exit 0
    fi
}



#会初始化一个json对象 命令执行结果会保存在json对象中
json_init
json_add_object result
json_close_object
case $method in
    "get_dns")
        get_dns
        ;;
    "get_imei")
        get_imei
        ;;
    "set_imei")
        set_imei $3
        ;;
    "get_mode")
        get_mode
        ;;
    "set_mode")
        set_mode $3
        ;;
    "get_network_prefer")
        get_network_prefer
        ;;
    "set_network_prefer")
        set_network_prefer $3
        ;;
    "get_lockband")
        get_lockband
        ;;
    "set_lockband")
        set_lockband $3
        ;;
    "get_neighborcell")
        get_neighborcell
        ;;
    "set_neighborcell")
        set_neighborcell $3
        ;;
    "base_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file base_info
        ;;
    "sim_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file sim_info
        ;;
    "cell_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file cell_info
        ;;
    "network_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file network_info
        ;;
    "info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file get_info
        ;;
esac
json_dump
