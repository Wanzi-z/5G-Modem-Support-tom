-- Copyright 2024 Siriling <siriling@qq.com>
module("luci.controller.modem", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require("luci.jsonc")
uci = luci.model.uci.cursor()
local script_path="/usr/share/modem/"
local run_path="/tmp/run/modem/"
local modem_ctrl = "/usr/share/modem/modem_ctrl.sh "

function index()
    if not nixio.fs.access("/etc/config/modem") then
        return
    end

	entry({"admin", "network", "modem"}, alias("admin", "network", "modem", "modem_info"), luci.i18n.translate("Modem"), 100).dependent = true
	--mwan配置
	entry({"admin", "network", "modem", "mwan_config"}, cbi("modem/mwan_config"), luci.i18n.translate("Mwan Config"), 1).leaf = true
	entry({"admin", "network", "modem", "modem_ttl"}, cbi("modem/modem_ttl"), luci.i18n.translate("TTL Config"), 50).leaf = true
	--sim卡配置
	entry({"admin", "network", "modem", "modem_sim"}, cbi("modem/modem_sim"), luci.i18n.translate("SIM Config"), 55).leaf = true
	entry({"admin", "network", "modem", "set_sim"}, call("setSIM"), nil).leaf = true
	entry({"admin", "network", "modem", "get_sim"}, call("getSIM"), nil).leaf = true
	--模块信息
	entry({"admin", "network", "modem", "modem_info"}, template("modem/modem_info"), luci.i18n.translate("Modem Information"),10).leaf = true
	entry({"admin", "network", "modem", "get_modem_cfg"}, call("getModemCFG"), nil).leaf = true
	entry({"admin", "network", "modem", "modem_ctrl"}, call("modemCtrl")).leaf = true
	--拨号配置
	entry({"admin", "network", "modem", "dial_overview"},cbi("modem/dial_overview"),luci.i18n.translate("Dial Overview"),20).leaf = true
	entry({"admin", "network", "modem", "dial_config"}, cbi("modem/dial_config")).leaf = true
	entry({"admin", "network", "modem", "get_modems"}, call("getModems"), nil).leaf = true
	entry({"admin", "network", "modem", "get_dial_log_info"}, call("getDialLogInfo"), nil).leaf = true
	entry({"admin", "network", "modem", "clean_dial_log"}, call("cleanDialLog"), nil).leaf = true
	--模块调试
	entry({"admin", "network", "modem", "modem_debug"},template("modem/modem_debug"),luci.i18n.translate("Modem Debug"),30).leaf = true
	entry({"admin", "network", "modem", "send_at_command"}, call("sendATCommand"), nil).leaf = true
	--插件设置
	entry({"admin", "network", "modem", "plugin_config"},cbi("modem/plugin_config"),luci.i18n.translate("Plugin Config"),40).leaf = true
	entry({"admin", "network", "modem", "modem_config"}, cbi("modem/modem_config")).leaf = true
	entry({"admin", "network", "modem", "modem_scan"}, call("modemScan"), nil).leaf = true
end

--[[
@Description 执行Shell脚本
@Params
	command sh命令
]]
function shell(command)
	local odpall = io.popen(command)
	local odp = odpall:read("*a")
	odpall:close()
	return odp
end

function translate_modem_info(result)
	modem_info = result["modem_info"]
	response = {}
	for k,entry in pairs(modem_info) do
		if type(entry) == "table" then
			key = entry["key"]
			full_name = entry["full_name"]
			if full_name then
				full_name = luci.i18n.translate(full_name)
			elseif key then
				full_name = luci.i18n.translate(key)
			end
			entry["full_name"] = full_name
			if entry["class"] then
				entry["class"] = luci.i18n.translate(entry["class"])
			end
			table.insert(response, entry)
		end
	end
	return response
end

function modemCtrl()
	local action = http.formvalue("action")
	local cfg_id = http.formvalue("cfg")
	local params = http.formvalue("params")
	local translate = http.formvalue("translate")
	if params then
		result = shell(modem_ctrl..action.." "..cfg_id.." ".."\""..params.."\"")
	else 
		result = shell(modem_ctrl..action.." "..cfg_id)
	end
	if translate == "1" then
		modem_more_info = json.parse(result)
		modem_more_info = translate_modem_info(modem_more_info)
		result = json.stringify(modem_more_info)
	end
	luci.http.prepare_content("application/json")
	luci.http.write(result)
end

--[[
@Description 执行AT命令
@Params
	at_port AT串口
	at_command AT命令
]]
function at(at_port,at_command)
	local command="source "..script_path.."modem_debug.sh && at "..at_port.." "..at_command
	local result=shell(command)
	result=string.gsub(result, "\r", "")
	return result
end

--[[
@Description 获取制造商
@Params
	at_port AT串口
]]
function getManufacturer(at_port)

	local manufacturer
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			manufacturer=modem_device["manufacturer"]
			return true --跳出循环
		end
	end)

	return manufacturer
end

--[[
@Description 获取模组拨号模式
@Params
	at_port AT串口
	manufacturer 制造商
	platform 平台
]]
function getMode(at_port,manufacturer,platform)
	local mode="unknown"

	if at_port and manufacturer~="unknown" then
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_mode "..at_port.." "..platform
		local result=shell(command)
		mode=string.gsub(result, "\n", "")
	end

	return mode
end

--[[
@Description 获取模组支持的拨号模式
@Params
	at_port AT串口
]]
function getModes(at_port)

	local modes
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			modes=modem_device["modes"]
			return true --跳出循环
		end
	end)

	return modes
end




--[[
@Description 获取模组信息
]]
function getModems()
	
	-- 获取所有模组
	local modems={}
	uci:foreach("modem", "modem-device", function (modem_device)
		config_name = modem_device[".name"]
		modem_name = modem_device["name"]
		cmd = modem_ctrl.."base_info "..config_name
		result = shell(cmd)
		json_result = json.parse(result)
		modem_info = json_result["modem_info"]
		tmp_info = {}
		name = {
			type = "plain_text",
			key = "name",
			value = modem_name
		}
		table.insert(tmp_info, name)
		for k,v in pairs(modem_info) do
			full_name = v["full_name"]
			if full_name then
				v["full_name"] = luci.i18n.translate(full_name)
			end
			table.insert(tmp_info, v)
		end
		table.insert(modems, tmp_info)
	end)
	
	-- 设置值
	local data={}
	data["modems"]=modems

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 获取拨号日志信息
]]
function getDialLogInfo()
	
	local command="find "..run_path.." -name \"modem*_dial.cache\""
	local result=shell(command)

	local log_paths=string.split(result, "\n")
	table.sort(log_paths)

	local logs={}
	local names={}
	local translation={}
	for key in pairs(log_paths) do

		local log_path=log_paths[key]

		if log_path ~= "" then
			-- 获取模组
			local tmp=string.gsub(log_path, run_path, "")
			local modem=string.gsub(tmp, "_dial.cache", "")
			local modem_name=uci:get("modem", modem, "name")

			-- 获取日志内容
			local command="cat "..log_path
			log=shell(command)

			-- 排序插入
			modem_log={}
			modem_log[modem]=log
			table.insert(logs, modem_log)

			--设置模组名
			names[modem]=modem_name
			-- 设置翻译
			translation[modem_name]=luci.i18n.translate(modem_name)
		end
	end

	-- 设置值
	local data={}
	data["dial_log_info"]=logs
	data["modem_name_info"]=names
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 清空拨号日志
]]
function cleanDialLog()
	
	-- 获取拨号日志路径
    local dial_log_path = http.formvalue("path")

	-- 清空拨号日志
	local command=": > "..dial_log_path
	shell(command)

	-- 设置值
	local data={}
	data["clean_result"]="clean dial log"

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end


function act_status()
	local e = {}
	e.index = luci.http.formvalue("index")
	e.status = luci.sys.call(string.format("busybox ps -w | grep -v 'grep' | grep '/var/etc/socat/%s' >/dev/null", luci.http.formvalue("id"))) == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end



function getModemCFG()

	local cfgs={}
	local translation={}

	uci:foreach("modem", "modem-device", function (modem_device)
		--获取模组的备注
		local network=modem_device["network"]
		local remarks=modem_device["remarks"]
		local config_name=modem_device[".name"]
		--设置模组AT串口
		local cfg = modem_device[".name"]
		local at_port=modem_device["at_port"]
		local name=modem_device["name"]:upper()
		local config = {}
		config["name"] = name
		config["at_port"] = at_port
		config["cfg"] = cfg
		table.insert(cfgs, config)
	end)

	-- 设置值
	local data={}
	data["cfgs"]=cfgs
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 获取拨号模式信息
]]
function getModeInfo()
	local at_port = http.formvalue("port")

	--获取值
	local mode_info={}
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then

			--获取制造商
			local manufacturer=modem_device["manufacturer"]
			if manufacturer=="unknown" then
				return true --跳出循环
			end

			--获取支持的拨号模式
			local modes=modem_device["modes"]

			--获取模组拨号模式
			local mode=getMode(at_port,manufacturer,modem_device["platform"])

			--设置模式信息
			mode_info["mode"]=mode
			mode_info["modes"]=modes

			return true --跳出循环
		end
	end)
	
	--设置值
	local modem_debug_info={}
	modem_debug_info["mode_info"]=mode_info

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(modem_debug_info)
end

--[[
@Description 设置拨号模式
]]
function setMode()
    local at_port = http.formvalue("port")
	local mode_config = http.formvalue("mode_config")

	--获取制造商
	local manufacturer=getManufacturer(at_port)

	--设置模组拨号模式
	local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_set_mode "..at_port.." "..mode_config
	shell(command)

	--获取设置好后的模组拨号模式
	local mode
	if at_port and manufacturer and manufacturer~="unknown" then
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_mode "..at_port
		local result=shell(command)
		mode=string.gsub(result, "\n", "")
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(mode)
end

--[[
@Description 获取网络偏好信息
]]
function getNetworkPreferInfo()
	local at_port = http.formvalue("port")
	
	--获取制造商
	local manufacturer=getManufacturer(at_port)

	--获取值
	local network_prefer_info
	if manufacturer~="unknown" then
		--获取模组网络偏好
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_network_prefer "..at_port
		local result=shell(command)
		network_prefer_info=json.parse(result)
	end

	--设置值
	local modem_debug_info={}
	modem_debug_info["network_prefer_info"]=network_prefer_info

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(modem_debug_info)
end


function getSimSlot(sim_path)
    local sim_slot = fs.readfile(sim_path)
    local current_slot = string.match(sim_slot, "%d")
    if current_slot == "0" then
        return "SIM2"
    else
        return "SIM1"
    end
end

function getNextBootSlot()
    local fw_print_cmd = "fw_printenv -n sim2"
    local nextboot_slot = shell(fw_print_cmd)
    if nextboot_slot == "" then
        return "SIM1"
    else
        return "SIM2"
    end
end

function writeJsonResponse(current_slot, nextboot_slot)
    local result_json = {}
    result_json["current_slot"] = current_slot
    result_json["nextboot_slot"] = nextboot_slot
    luci.http.prepare_content("application/json")
    luci.http.write_json(result_json)
end

function getSIM()
    local sim_path = "/sys/class/gpio/sim/value"
    local current_slot = getSimSlot(sim_path)
    local nextboot_slot = getNextBootSlot()
    writeJsonResponse(current_slot, nextboot_slot)
end

function setSIM()
    local sim_gpio = "/sys/class/gpio/sim/value"
    local modem_gpio = "/sys/class/gpio/4g/value"
    local sim_slot = http.formvalue("slot")
    local pre_detect = getSimSlot(sim_gpio)
    
    local reset_module = 1
    if pre_detect == sim_slot then
        reset_module = 0
    end
    if sim_slot == "SIM1" then
        sysfs_cmd = "echo 1 >"..sim_gpio
        fw_setenv_cmd = "fw_setenv sim2"
    elseif sim_slot == "SIM2" then
        sysfs_cmd = "echo 0 >"..sim_gpio
        fw_setenv_cmd = "fw_setenv sim2 1"
    end
    shell(sysfs_cmd)
    shell(fw_setenv_cmd)
    if reset_module == 1 then
        shell("echo 0 >"..modem_gpio)
        os.execute("sleep 1")
        shell("echo 1 >"..modem_gpio)
    end
    local current_slot = getSimSlot(sim_gpio)
    local nextboot_slot = getNextBootSlot()
    writeJsonResponse(current_slot, nextboot_slot)
end


--[[
@Description 发送AT命令
]]
function sendATCommand()
    local at_port = http.formvalue("port")
	local at_command = http.formvalue("command")

	local response={}
    if at_port and at_command then
		response["response"]=at(at_port,at_command)
		response["time"]=os.date("%Y-%m-%d %H:%M:%S")
    end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(response)
end

--[[
@Description 模组扫描
]]
function modemScan()

	local command="source "..script_path.."modem_scan.sh && modem_scan"
	local result=shell(command)

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end


function reloadDial()
	local command="/etc/init.d/network reload"
	shell(command)
	local response={}
	response["response"]="reload dial"
	response["time"]=os.date("%Y-%m-%d %H:%M:%S")
	luci.http.prepare_content("application/json")
	luci.http.write_json(response)
end
