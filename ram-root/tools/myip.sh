#!/bin/ash
#set -x

valid_ip() {
  local  ip=$1
  [[ "$ip" == "$(echo ${ip} | grep -E '(([0-9]{1,3})\.){3}([0-9]{1,3}){1}' | \
     grep -vE '25[6-9]|2[6-9][0-9]|[3-9][0-9][0-9]')" ]] && return 0
  return 1
}

[[ $(which curl &>/dev/null) ]] || {
  opkg -V0 update &>/dev/null
  opkg -V0 install curl &>/dev/null
}

[[ $(which curl &>/dev/null) ]] || {
  logger -p info -t MYIP "'curl' must be installed"
  exit 1
}

for site in ipaddr.pub/cli ipecho.net/plain icanhazip.com ifconfig.me \
            ipconfig.in/ip diagnostic.opendns.com/myip
do
  if valid_ip $(curl -s $site 2>/dev/null); then
    echo ${ip}
    exit 0
  fi
done

echo ???.???.???.???
exit 1
