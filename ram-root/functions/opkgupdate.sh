opkg_update () {
  local _OK_='\033[0;32m\xe2\x9c\x93\033[0m'
  local _FAIL_='\033[0;31m\xe2\x9c\x97\033[0m'
  local __OK__='\033[0;32m[\xe2\x9c\x93]\033[0m'
  local __FAIL__='\033[0;31m[\xe2\x9c\x97]\033[0m'
  local _WARNING_='\033[0;33mWARNING\033[0m'
  local _ERROR_='\033[0;31mERROR\033[0m'

  local _COL_GRN="\e[32m"
  local _COL_BLU="\e[34m"
  local _COL_RED="\e[31m"
  local _COL_RST="\e[0m"

  local time=0
  local interactive=${1}

  [[ $# -ge 1 && "$interactive" != "-i" ]] && interactive="-i"
  local count=$(echo $(ls /tmp/cache/apk/) | wc -w )
  [[ -d /tmp/cache/apk && $count -gt 0 ]] && time=$(( $(date +%s) - $(date -r /tmp/cache/apk +%s) ))

  [[ $time -ge 600 ]] && time=0

  if [[ $time -eq 0 ]]; then
    if ! ( ping -s 1 -c 1 downloads.openwrt.org &>/dev/null ); then
      echo -e "${_COL_RED}No internet connection${_COL_RST}"
      return 1;
    fi

    echo -e "${_COL_GRN}Updating repositories${_COL_RST}"
      if ( apk update ); then
        echo -e ${_OK_}
      else
        echo -e ${_FAIL_}
      fi
    echo
  fi
}
