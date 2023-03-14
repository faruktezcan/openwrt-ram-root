sleep_ms() {
  if which /usr/libexec/sleep-coreutils >/dev/null; then
    sleep $(awk "BEGIN {print ${1:-50}/100}")
  else
    let __sleepms__+=${1:-50} # (default 50 ms)
    local uptime=$(sed -e 's/ .*//' -e 's/\.//' /proc/uptime)
    [[ ${__sleepms__} -lt ${uptime} ]] && __sleepms__=${uptime}
    while [[ ${__sleepms__} -gt ${uptime} ]]; do uptime=$(sed -e 's/ .*//' -e 's/\.//' /proc/uptime); done
    export __sleepms__
  fi
}
