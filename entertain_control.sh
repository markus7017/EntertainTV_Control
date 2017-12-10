#!/bin/bash
# requires "apt-get install netcat etherwake"

#${var#*SubStr}  # will drop begin of string upto first occur of `SubStr`
#${var##*SubStr} # will drop begin of string upto last occur of `SubStr`
#${var%SubStr*}  # will drop part of string from last occur of `SubStr` to the end
#${var%%SubStr*} # will drop part of string from first occur of `SubStr` to the end

log=/usr/share/openhab2/log/entertain_control.log
#log=/dev/stdout

function e {
	echo $1 >> $log
}  


#
# md5() : return MD5 digist on input string
# expects:
#	$1: String to hash
#	$2: name of the return var
# returns: MD5 digest
#
function md5_hash {
	digest=$(printf '%s' "$1" | md5sum)
	digest=$(echo "$digest" | tr /a-z/ /A-Z/)
	digest=${digest%% *}
}

function get_mac {
local platform

	mac_addr=""
	platform=$(uname)
	if [ "$platform" == "Darwin" ]; then
		en0_mac=$(ifconfig en0 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' 2>&1)
		en1_mac=$(ifconfig en1 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' 2>&1)
		ip_addr=$(ifconfig  | grep 'inet '| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $2}' 2>&1)
	else
		en0_mac=$(ip link show eth0 2>&1 | awk '/ether/ {print $2}' 2>&1)
		en1_mac=$(ip link show eth1 2>&1 | awk '/ether/ {print $2}' 2>&1)
		ip_addr=$(ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}' 2>&1)
	fi

	mac_addr="$en0_mac"
	if [ "$mac_addr" == "" ]; then
		mac_addr="$en1_mac"
	fi
	mac_addr=$(echo "$mac_addr" | tr /a-z/ /A-Z/)
}

function entertain_initialize {
	get_mac
	remote_ip="192.168.6.206"
	remote_mac="AC:6F:BB:29:8D:E3"
	remote_port="49152"
	local_ip="$ip_addr"
	local_port="49154"
	echo "$local_ip:$local_port -> $remote_ip:$remote_port; local MAC=$mac_addr"

	md5_hash "$mac_addr"
	mac_hash="$digest"
	terminalID="$mac_hash"
	echo "terminalID='$terminalID'" >> $log

	userID="5903A68E8E31CF7EFC9718C635FC037D"
	pairingDeviceID="$terminalID"
	friendlyName="oh-pi"
	pairingCode=""
	dev_paired="no"

	entertain_checkdev
}

#
# entertain_checkdev(): Check if receiver is online
# expects: -
# returns: set global var dev_status to ON or OFF
function entertain_checkdev {

	OUTPUT=$(ping -c 1 -W 1 $remote_ip)
	if [ $? -ne 0 ]; then
		echo "Receiver is OFF" >> $log
		dev_status="OFF"
		return 1
	else
		dev_status="ON"
		curl --silent -A "Darwin/16.5.0 UPnP/1.0 HUAWEI_iCOS/iCOS V1R1C00 DLNADOC/1.50" http://$remote_ip:$remote_port/upnp/service/des/X-CTC_RemotePairing.xml -o $tmp/request_service.log
		return 0
	fi
}

#
# entertain_wakeup
#
function entertain_wakeup {
	if [ "$dev_status" == "OFF" ]; then
		echo "Wakeup Receiver (MAC=$remote_mac)"
		wakeonlan $remote_mac >> $log
ping -c 60 -W 1 $remote_ip
		until ping -c 1 -W 1 $remote_ip &> /dev/null; do :; done
	fi
	entertain_checkdev
}

#
# entertain_pair(): initiate pairing process
# expects:
#	remote_ip:remote_port set correctly
# fills:
#	pairingCode, verificationCode required to verify pairing
#
function entertain_pair {
local res result

	dev_paired="no"

	# Start UPnP Event listener
	pkill -fx 'nc -v -l $local_port' >> $log
	rm -f ./.ncin1 ./.ncout1 >> $log
	mkfifo ./.ncin1 ./.ncout1 >> $log
	exec 5<>./.ncin1 6<>./.ncout1
	nc -v -l $local_port <&5 >&6 &

	rm -f ./.ncin2 ./.ncout2
	mkfifo ./.ncin2 ./.ncout2
	exec 7<>./.ncin2 8<>./.ncout2
	nc -w 10 $remote_ip $remote_port <&7 >&8 &
	
	# Subscribe to Pairing events
	printf "SUBSCRIBE /upnp/service/X-CTC_RemotePairing/Event HTTP/1.1\r\nHOST: $remote_ip:$remote_port\r\nCALLBACK: <http://$local_ip:$local_port/>\r\nNT: upnp:event\r\nTIMEOUT: Second-300\r\nCONNECTION: close\r\n\r\n" >&7

sleep 3

	echo "Send pairing request (pairingDeviceID='$pairingDeviceID', friendlyName='$friendlyName', userID='$userID')"
	printf "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>\n<u:X-pairingRequest xmlns:u=\"urn:schemas-upnp-org:service:X-CTC_RemotePairing:1\">\n<pairingDeviceID>$pairingDeviceID</pairingDeviceID>\n<friendlyName>$friendlyName</friendlyName>\n<userID>$userID</userID>\n</u:X-pairingRequest>\n</s:Body></s:Envelope>" > $tmp/soap_pair.xml 
	curl --silent -A "Darwin/16.5.0 UPnP/1.0 HUAWEI_iCOS/iCOS V1R1C00 DLNADOC/1.50" -H 'Accept:' --header "Content-Type: text/xml;charset=UTF-8"  --header 'SOAPACTION: "urn:schemas-upnp-org:service:X-CTC_RemotePairing:1#X-pairingRequest"' --header "CONNECTION: close" --data @$tmp/soap_pair.xml      http://$remote_ip:$remote_port/upnp/service/X-CTC_RemotePairing/Control -o $tmp/request_pair.log
	OUTPUT=$(grep "<result>" $tmp/request_pair.log)
	res=${OUTPUT#*<result>}
	res=${res%%<*}
	echo "Result=$res"
	if [ "$res" != "0" ]; then
		printf "Pairing request failed: $res\n$OUTPUT"
		return 1
	fi
	
	echo "Waiting for Pairing Code..."
	OUTPUT=""
	result=""
	while read -t 10 result; do
    	line="`echo "$result" | tr -d '\r'`"
	    OUTPUT="$OUTPUT
$line"
		echo "$line" | grep "X-pairingCheck:" >/dev/null && break
	done <&6
	pairingCode=${OUTPUT#*X-pairingCheck:}
	pairingCode=${pairingCode%%<*}
	if [ "$pairingCode" == "" ]; then
		printf "Unable to get pairingCode!\n$OUTPUT"
		return 2
	fi

	echo "Verify pairing (pairingCode='$pairingCode')"
	verificationCode=""
	code_input="$pairingCode$pairingDeviceID$userID"
	echo "code_input='$code_input'"
	md5_hash "$code_input"
	verificationCode="$digest"
	echo "verificationCode=$verificationCode"

	printf "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>\n<u:X-pairingCheck xmlns:u=\"urn:schemas-upnp-org:service:X-CTC_RemotePairing:1\">\n<pairingDeviceID>$pairingDeviceID</pairingDeviceID>\n<verificationCode>$verificationCode</verificationCode>\n</u:X-pairingCheck>\n</s:Body></s:Envelope>" > $tmp/soap_pairver.xml
	curl --silent -A "Darwin/16.5.0 UPnP/1.0 HUAWEI_iCOS/iCOS V1R1C00 DLNADOC/1.50" -H 'Accept:' --header "Content-Type: text/xml;charset=UTF-8"  --header 'SOAPACTION: "urn:schemas-upnp-org:service:X-CTC_RemotePairing:1#X-pairingCheck"'   --header "CONNECTION: close" --data @$tmp/soap_pairver.xml   http://$remote_ip:$remote_port/upnp/service/X-CTC_RemotePairing/Control  -o $tmp/request_pairver.log
	OUTPUT=$(grep "<pairingResult>" $tmp/request_pairver.log)
	res=${OUTPUT#*<pairingResult>}
	res=${res%%<*}
	if [ "$res" != "0" ]; then
		printf "Unable to verify pairing: $res\n$OUTPUT"
		return 2
	fi
	echo "Successful."
	dev_paired="yes"
	return 0
}

#
# entertain_presskeys: Send one or two keys to the receiver
# expects:
#	successful connect to the receiver
#	$1 = key to send
#		"P" = press power button (toggle)
#		1..99 = key to send
#
function entertain_presskeys {
local key1 key2

	if [ "$1" == "P" ]; then # Power
		echo "Press Power"
		sendkey "0x0100"
		return 0
	fi

	key1=$(($1 / 10))
	key2=$(($1 % 10))
	echo "Key1='$key1', Key2='$key2'"
	if [ $key1 -gt 0 ]; then
		echo "Press $key1"
		sendkey "0x003$key1"
	fi
	echo "Press $key2"
	sendkey "0x003$key2"
}

function sendkey {
local res

	keyCode="$1"
	echo "Send key '$keyCode'"
	printf "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>\n<u:X_CTC_RemoteKey xmlns:u=\"urn:schemas-upnp-org:service:X-CTC_RemoteControl:1\">\n<InstanceID>0</InstanceID>\n<KeyCode>keyCode=$keyCode^$pairingDeviceID:$verificationCode^userID:$userID</KeyCode>\n</u:X_CTC_RemoteKey>\n</s:Body></s:Envelope>" > $tmp/soap_key.xml
	curl --silent -A "Darwin/16.5.0 UPnP/1.0 HUAWEI_iCOS/iCOS V1R1C00 DLNADOC/1.50" -H 'Accept:' --header "Content-Type: text/xml;charset=UTF-8"  --header 'SOAPACTION: "urn:schemas-upnp-org:service:X-CTC_RemoteControl:1#X_CTC_RemoteKey"'  --header "CONNECTION: close" --data @$tmp/soap_key.xml http://$remote_ip:$remote_port/upnp/service/X-CTC_RemoteControl/Control  -o $tmp/request_sendkey.log
	OUTPUT=$(grep "<errorCode>" $tmp/request_sendkey.log)
	res=${OUTPUT#*<errorCode>}
	res=${res%%<*}
	echo "Result=$res"
}


#
# entertain_close: close NC connections
#
function entertain_close {
	rm -f ./.ncin1 ./.ncout1
	rm -f ./.ncin2 ./.ncout2
}


#
# main:
#
	echo Telekom Entertain Control
	OUTPUT=$(pwd)		# get working dir
	tmp="$OUTPUT/tmp"
	echo TMP-Dir=$tmp > $log
#	if [ ! -f $tmp/* ]; then
#		mkdir $tmp 2>&1 >> $log
#	fi
	



	entertain_initialize
	
	if [ "$1"  == "log" ]; then
		log="/dev/stdout"
 		shift
 	fi

	if [ "$1"  == "status" ]; then
		if [ "$dev_status" == "ON" ]; then
			echo "Receiver is powered ON"
		else
			echo "Receiver is powered OFF"
		fi
	elif [ "$1"  == "on" ]; then
was_on=$dev_status
		entertain_wakeup
		entertain_pair
		if [ "$dev_paired" == "yes" ]; then
			if [ "$was_on"  == "OFF" ]; then
				entertain_presskeys "P"
			fi
		else
			dev_status="OFF"
		fi
	elif [ "$1"  == "off" ]; then
		entertain_checkdev
		if [ "$dev_status"  == "ON" ]; then
			entertain_pair
			entertain_presskeys "P"
			dev_status="OFF"
		fi
	elif [ "$1"  == "presskey" ]; then
		entertain_checkdev
		if [ "$dev_status"  == "ON" ]; then
			entertain_pair
			entertain_presskeys "$2"
		fi
	else
			entertain_checkdev
			if [ "$dev_status"  == "OFF" ]; then
				entertain_wakeup
			fi
			entertain_pair
  	fi

	echo "$dev_status"
	entertain_close

	exit 0


