#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"
source "${SCRIPT_DIR}/modem_util.sh"

#模组配置初始化
modem_init()
{
    m_log "info" "Clearing all modem configurations"
    #清空模组配置
    local modem_count=$(uci -q get modem.@global[0].modem_number)
    for i in $(seq 0 $((modem_count-1))); do
        #删除该模组的配置
        uci batch <<EOF
del modem.modem${i}.data_interface
del modem.modem${i}.path
del modem.modem${i}.network
del modem.modem${i}.network_interface
del modem.modem${i}.ports
del modem.modem${i}.at_port
del modem.modem${i}.name
del modem.modem${i}.manufacturer
del modem.modem${i}.define_connect
del modem.modem${i}.platform
del modem.modem${i}.modes
EOF
    done
    uci set modem.@global[0].modem_number=0
    uci commit modem
    m_log "info" "All module configurations cleared"
}

modem_init
