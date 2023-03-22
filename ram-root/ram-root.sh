#!/bin/ash
#set -xv # debug

# Performs ext-root from ram drive as PIVOT root
# By Faruk Tezcan  'tezcan.faruk@gmail.com'



__list_contains() { # returns 1 if $1 doesn't contain $2
  [[ "${1%% ${2} *}" == "${1}" ]] && return 1
  return 0
}

#__list_contains() { # returns 1 if $1 doesn't contain $2
#  local T="${1/${2}/}"
#  [[ ${#T} -eq ${#1} ]] && return 1
#  return 0
#}

__occurs() { # check if $1 (separated with $3) contains $2 & return the # of occurances
  echo "${1}" | tr {{"${3:-" "}"}} {{'\n'}} | grep -F -c -x "${2}"
}

__lowercase() { # converts $1 to lowercase & sets $2 as a variable with result if $2 defined
  local __resultvar=${2}
  local __result=$(echo "${1}" | awk '{print tolower($0)}')
  [[ "$__resultvar" ]] && eval $__resultvar="'$__result'" || echo -n "$__result"
}

__identity_file() { # lists identity file(s)
  find /etc/dropbear/dropbear_* | while read -r name; do echo -n "-i ${name} "; done
}

__wait_for_network() { # waits until local network is ready up to NETWORK_WAIT_TIME
  ubus -t ${NETWORK_WAIT_TIME} wait_for network 2>/dev/null
}

__printf() {
  [[ -z "${1}" ]] && { echo "Empty!"; return 1; }

#  if [[ $1 =~ ^[+-]?[0-9]+$ ]]; then # Integer
#  elif [[ $1 =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then # Float
#  elif [[ $1 =~ [0-9] ]]; then # Mixed
#  else # then

  if [[ ${1} =~ ^[+-]?[0-9]+$ ]]; then # "Integer!"
    echo ${1} | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta'
  elif [[ ${1} =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then # "Float!"
    echo "$( echo ${1} | cut -d'.', -f1 | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta' ).$(echo $1 | cut -d'.', -f2)"
  else
    echo ${1} | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta'
  fi

  return 0
}

__beep() {
  [[ "${VERBOSE}" == "Y" ]] && echo -e "\a"
}

do_exec() { # <command> executes a command
  local cmd="${@}"
  do_logger "Info: executing '${cmd}'"
  ${cmd} || do_error "Error: command failed. Return code: $?"
}

do_logger() { # log msg
  logger ${STDERR} -p info -t ram-root "${1}"
}

do_error() { # <error message> <seconds> $1-mesage text $2-seconds(default=30)
  local secs=${2:-30}
  local name="/etc/rc.d/???ram-root"
  rm -f ${name} "${OLD_ROOT}${name}" # remove autostart
  sync
  do_logger "${1}"
  do_logger "Error: stopping 'ram-root' process"
  [[ $(__occurs "init backup" ${OPT}) -gt 0 ]] && exit 1
  [ "${VERBOSE}" == "Y" ] && {
    echo -e "\a\nRebooting in $secs seconds\nPress 'Ctrl+C' to cancel"
    do_countdown ${secs}
  }
  reboot &
  sleep 30
  reboot -f &
  exit 1
}

do_countdown() { # <seconds> $1-seconds(default=60)
  local secs=${1:-60}
  while [ ${secs} -gt 0 ]
  do
    printf "\a\r%2d" ${secs}
    secs=$(( ${secs}-1 ))
    sleep 1
  done
  echo
}

do_rm() { # removes dir or file(s)
  do_exec rm -Rf ${@}
}

do_mklink() { # makes symlink $1-file/dir $2-destination
  [[ -L ${2} ]] || do_exec ln -sf ${1} ${2}
}

do_pidmsg() { # waits until given pid job is completed $1-pid#  2-backup name
  while [[ $(ps | awk '{print $1}' | grep -c ${1}) -gt 0 ]]; do sleep 1; done
  do_logger "Info: backup is created in ${2}"
}

do_backup() { # creates ram-root backup
  local dir="/overlay/upper/"
  local file="/tmp/ram-root.backup"

  local backup_size=$( tar -C ${dir} ${EXCL} ${INCL} -c -z -f - . | wc -c )
  do_logger "Info: backup size = $( __printf ${backup_size} ) bytes"

  local free_memory=$( grep -i 'MemAvailable' /proc/meminfo | awk '{print $2*1024}' )
  do_logger "Info: available memory = $( __printf ${free_memory} ) bytes"

  [[ ${backup_size} -gt $(( ${free_memory} / 2 )) ]] && do_error "Error: not enough memory to carry on"

  if ${LOCAL_BACKUP}; then
    local share=${LOCAL_BACKUP_SHARE}
    mkdir -p ${share}
    local server_free_space=$( df -kP ${share} | awk '$1 != "Filesystem" {print $4*1024}' )
  else
    local share=${SHARE}
    local server_free_space=$( ${SSH_CMD} "mkdir -p ${share}; df -kP ${share}" )
    server_free_space=$( echo "${server_free_space}" | awk '$1 != "Filesystem" {print $4*1024}' )
  fi
  do_logger "Info: ${SERVER} free space = $( __printf ${server_free_space} ) bytes"

  [[ ${backup_size} -gt ${server_free_space} ]] && do_error "Error: backup size is too big"

  local name="${share}/${BACKUP_FILE}.gz"
  local mv_cmd="[[ -f ${name} ]] && mv -f ${name} ${name}~"

  if ${LOCAL_BACKUP}; then
    tar -C ${dir} ${EXCL} ${INCL} -c -z -f ${name} . >/dev/null
    do_logger "Info: backup is created in ${name}"
  else
    do_logger "Info: backup is running in background"
    nice -n 19 tar -C ${dir} ${EXCL} ${INCL} -c -z -f - . | ${SSH_CMD} "${mv_cmd}; cat > ${name}" >/dev/null &
    do_pidmsg $! "${SERVER}:${name}" &
  fi

  __beep
}

do_chkconnection() { # checks internet connection $1-seconds(default=60) $2-do_error (default Y)
  ${LOCAL_BACKUP} && return 0

  __wait_for_network
  if which netcat >/dev/null; then
    local secs=${1:-60}
    do_logger "Info: checking connection on server '${SERVER}' port '${PORT}'"
    while [[ ${secs} -gt 0 ]]
    do
      netcat -w 1 -z ${SERVER} ${PORT} >/dev/null && return 0
      [ "${VERBOSE}" == "Y" ] && printf "\a\r%2d" ${secs}
      secs=$(( ${secs}-1 ))
    done

    echo
    local msg="Error: connection lost to server '${SERVER}' port '${PORT}'"
    [[ "$2" != "N" ]] && do_error "${msg}"
    do_logger "${msg}"
    return 1
  else
    do_error "'netcat' package must be installed"
    return 1
  fi
}

do_init() { # server setup
  if ${LOCAL_BACKUP}; then
    mkdir -p ${SHARE}
    return 0
  fi

  local key_types="rsa"
  case ${VERSION} in
    2*) key_types="rsa ed25519" ;;
  esac

  do_logger "Info: setting up first time"

  for key_type in ${key_types}
  do
    local key_file="/etc/dropbear/dropbear_${key_type}_host_key"
    [[ -f ${key_file} ]] || do_exec dropbearkey -t ${key_type} -f ${key_file}
    do_mklink ${key_file} /root/.ssh/id_${key_type}
    do_mklink ${key_file} /root/.ssh/id_dropbear

    local key=$(dropbearkey -y -f ${key_file} | grep "ssh-")
    local name=$(echo ${key} | awk '{print $3}')
    local cmd="touch /etc/dropbear/authorized_keys; \
               sed -i '/${key_type}/ s/${name}/!@@@!/' /etc/dropbear/authorized_keys; \
               sed -i '/^$/d; /!@@@!/d' /etc/dropbear/authorized_keys; \
               echo ${key} >> /etc/dropbear/authorized_keys"
    ${SSH_CMD} "${cmd}" || do_error "Error: server '${SERVER}' setup not completed. Return code: $?"
  done

  do_mklink /ram-root/init.d/ram-root /etc/init.d
  name="/root/.profile"
  touch ${name}
  sed -i '/shell_prompt/d' ${name}
  echo -e "\n. /ram-root/shell_prompt" >> ${name}
}

do_pre_proc_packages() { # installs non-backable, non-preserved packages after reboots
  [[ -z "${PACKAGES}" ]] && return 0

  do_logger "Info: installing package(s) -> ${PACKAGES}"
  do_exec mkdir -p ${NEW_OVERLAY}/lower
  LOWER_NAME="${NEW_OVERLAY}/lower:"

  cp -f /etc/opkg.conf /tmp/opkg_ram-root.conf
  echo "dest ram-root ${NEW_OVERLAY}/lower" >> /tmp/opkg_ram-root.conf
  do_update_repositories
  for name in ${PACKAGES}; do do_install ${name} "/tmp/opkg_ram-root.conf" "ram-root"; done
  rm -f /tmp/opkg_ram-root.conf
}

do_update_repositories() {
  type opkg_update >/dev/null || source /ram-root/functions/opkgupdate.sh
  opkg_update ${INTERACTIVE}; [[ $? -gt 0 ]] && do_error "Error: updating repository failed"
}

do_install() { # installs a package $1-list of packages $2-config_file(default=/etc/opkg.conf) $3-destination(default=root)
  local name=${1}
  local conf_file=${2:-"/etc/opkg.conf"}
  local dest_name=${3:-"root"}

  [[ -n "$(opkg status ${name})" ]] && { do_logger "Notice: '${name}' already installed"; return; }
  [[ -z "$(opkg find ${name})" ]] && do_error "Error: '${name}' not found"

  do_exec opkg install -f ${conf_file} -d ${dest_name} ${name}
}


###################################
#       PRE INSTALL PROCEDURE     #
###################################
pre_proc() {
  do_rm /tmp/ram-root-active
  touch /tmp/ram-root.failsafe

  do_logger "Info: creating ram disk"
  do_exec mkdir -p ${NEW_OVERLAY}
  do_exec mount -t tmpfs -o rw,nosuid,nodev,noatime tmpfs $NEW_OVERLAY
  do_exec mkdir -p ${NEW_ROOT} ${NEW_OVERLAY}/upper ${NEW_OVERLAY}/work

  do_pre_proc_packages

  if [[ "${BACKUP}" == "Y" ]]; then
    ${LOCAL_BACKUP} \
      && local name="${LOCAL_RESTORE_SHARE}/${BACKUP_FILE}.gz" \
      || local name="${SHARE}/${BACKUP_FILE}.gz"

    case ${OPT} in
      start)
        local backupExist=false
        ${LOCAL_BACKUP} \
          && { [[ -f ${name} ]] && backupExist=true; } \
          || { ${SSH_CMD} "[[ -f ${name} ]] && return 0 || return 1" && backupExist=true; }

        if ${backupExist}; then
          do_logger "Info: restoring backup file '${name}'"
          [[ "${VERBOSE}" == "Y" ]] && start_progress
          ${LOCAL_BACKUP} \
            && do_exec tar -C ${NEW_OVERLAY}/upper/ -x -z -f ${name} \
            || do_exec ${SSH_CMD} "gzip -dc ${name}" | tar -C ${NEW_OVERLAY}/upper/ -x -f -
          [[ "${VERBOSE}" == "Y" ]] && kill_progress
        else
          do_logger "Notice: backup file '${name}' not found"
        fi
        ;;

      reset)
        do_logger "Info: bypassing backup file '${name}'"
        ;;
    esac

  fi

  sync
} # pre_proc

###################################
#     POST INSTALL PROCEDURE      #
###################################
post_proc() {
  do_exec /etc/init.d/network restart

  [ "${VERBOSE}" == "Y" ] && echo -e "\a\nInfo: *** Re-connect to the router after ${NETWORK_WAIT_TIME} seconds if your console does not respond ***"
  do_chkconnection ${NETWORK_WAIT_TIME}

  local ft=""; ls -1A /etc/rc.d | grep ^S | grep -v ram-root | while read name
  do
    [[ -f ${OLD_ROOT}/etc/rc.d/${name} ]] || {
      [[ -z ${ft} ]] && { do_logger "Info: starting services enabled in 'ram-root'"; ft="Y"; }
      do_exec /etc/init.d/${name:3} start
    }
  done

  ft=""; ls -1A ${OLD_ROOT}/etc/rc.d | grep ^S | grep -v ram-root | while read name
  do
    [[ -f /etc/rc.d/${name} ]] || {
      [[ -z ${ft} ]] && { do_logger "Info: stopping services disabled in 'ram-root'"; ft="Y"; }
      do_exec /etc/init.d/${name:3} stop
    }
  done

  [[ -n "${START_SERVICES}" ]] && {
    do_logger "Info: starting service(s) in '${CONFIG_NAME}'"
    for name in ${START_SERVICES}
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} start || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "${RESTART_SERVICES}" ]] && {
    do_logger "Info: re-starting service(s) in '${CONFIG_NAME}'"
    for name in ${RESTART_SERVICES}
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} restart || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "${STOP_SERVICES}" ]] && {
    do_logger "Info: stopping service(s) in ${CONFIG_NAME}'"
    for name in ${STOP_SERVICES}
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} stop || do_logger "Notice: ${name} not found"
    done
  }

  [[ -f ${RCLOCAL_FILE} ]] && do_exec sh ${RCLOCAL_FILE}
  [[ $(ls -1A /etc/rc.d | grep -c "S??uhttpd") -gt 0 ]] && do_exec /etc/init.d/uhttpd restart
  [[ -f /etc/init.d/zram ]] && if /etc/init.d/zram enabled; then sync; do_exec /etc/init.d/zram restart; fi

  do_rm ${NEW_ROOT} ${NEW_OVERLAY} ${RAM_ROOT} /rom /tmp/root /tmp/ram-root.failsafe # some cleanup
  do_mklink ${OLD_ROOT}${RAM_ROOT} /

  echo "PIVOT" > /tmp/ram-root-active

  [[ "${BACKUP}" == "Y" && "${OPT}" == "init" ]] && do_backup # 1st backup

  sync
} # post_proc

###################################
#             MAIN                #
###################################
#trap "exit 1" INT TERM
#trap "kill 0" EXIT

# BASE="${0##*}"

[[ $# -ne 1 ]] && { do_logger "Error: need an option to run"; exit 1; }

OPT=${1}

OLD_ROOT="/old_root"
RAM_ROOT="/ram-root"

CONFIG_NAME="ram-root.cfg"
[[ -f ${RAM_ROOT}/${CONFIG_NAME} ]] || { do_logger "Error: config file '${RAM_ROOT}/${CONFIG_NAME}' not exist"; exit 1; }
source ${RAM_ROOT}/${CONFIG_NAME}

[[ "${DEBUG}" == "Y" ]] && set -xv
eval $(grep -e 'VERSION=\|BUILD_ID=' /usr/lib/os-release)
[[ "${INTERACTIVE_UPGRADE}" == "Y" ]] && INTERACTIVE="-i"

if [[ ! -f /tmp/ram-root-active ]]; then
  [[ $(__occurs "stop backup upgrade" $OPT) -gt 0 ]] && { do_logger "Info: 'ram-root' not running"; exit 1; }
else
  [[ $(__occurs "init start reset" $OPT) -gt 0 ]] && { do_logger "Info: 'ram-root' already running"; exit 1; }
fi

if [[ -f /tmp/ram-root.failsafe ]]; then
  do_rm /etc/rc.d/???ram-root
  do_logger "Info: previous attempt was not successful. Disabling auto-run"
  do_logger "Info: fix the problem & run 'rm /tmp/ram-root.failsafe' command to continue"
  [[ -z "${PS1}" ]] && exit 1
  type ask_bool >/dev/null || source /ram-root/functions/askbool.sh
  ask_bool ${INTERACTIVE} -t 5 -d N "\a\nDo you want to remove it now" && do_rm /tmp/ram-root.failsafe
  exit 1
fi

SYSTEM_IP=$(ifconfig br-lan | grep "inet addr" | cut -f2 -d':' | cut -f1 -d' ')
LOCAL_BACKUP=false
[[ $(__occurs "$(__lowercase ${HOSTNAME}) ${SYSTEM_IP} localhost 127.0.0.1" $(__lowercase ${SERVER}) ) -gt 0 ]] && { SERVER=${SYSTEM_IP}; LOCAL_BACKUP=true; }
LOCAL_RESTORE_SHARE=${SHARE}
LOCAL_BACKUP_SHARE=${SHARE}
[[ ${LOCAL_BACKUP} && $(__occurs ${SHARE} ${OLD_ROOT}) -eq 0 ]] && LOCAL_BACKUP_SHARE="${OLD_ROOT}${SHARE}" # make sure backup goes to < OLD-ROOT >
SHARE="${SHARE}/${HOSTNAME}"
SERVER_SHARE="${SERVER}:${SHARE}"
NEW_ROOT="/tmp/root"
NEW_OVERLAY="/tmp/overlay"
BACKUP_FILE="${BUILD_ID}.tar"
SSH_CMD="ssh -q $(__identity_file) ${USER}@${SERVER}/${PORT}"
#SCP_CMD="scp -q -p $(__identity_file) -P ${PORT}"

[[ -f ${EXCLUDE_FILE} && $(wc -c ${EXCLUDE_FILE} | cut -f1 -d' ') -gt 0 ]] && EXCL="-X ${EXCLUDE_FILE}"
[[ -f ${INCLUDE_FILE} && $(wc -c ${INCLUDE_FILE} | cut -f1 -d' ') -gt 0 ]] && INCL="-T ${INCLUDE_FILE}"
[[ -z "${PS1}" ]] && VERBOSE="N"
[[ "${OPT}" == "init" && -n "${PS1}" ]] && VERBOSE="Y"

if [[ "${VERBOSE}" == "Y" ]]; then
  type print_progress >/dev/null || source /ram-root/functions/printprogress.sh
  STDERR="-s"
fi

case ${OPT} in
  init|start|reset)
    ;;

  backup|stop)
    [[ -f /tmp/ram-root-active ]] || { do_logger "Info: 'ram-root' not running"; exit 1; }
    [[ "${BACKUP}" == "Y" ]] || do_logger "Info: backup option is not selected" && {
      if do_chkconnection 60 "N"; then
        do_backup; sync; [[ "${OPT}" == "stop" ]] && do_error "Rebooting" 5
        exit 0
      fi
      do_logger "Info: no response from server '${SERVER}' port '${PORT}'"
    }
    [[ "${OPT}" == "stop" ]] && do_error "Rebooting" 5
    exit 1
    ;;

  upgrade)
    ${RAM_ROOT}/tools/opkgupgrade.sh -i
    exit 0
    ;;

  *)
    do_logger "Info: invalid option: '${OPT}'"
    exit 1
    ;;
esac

[[ -d ${NEW_ROOT}    ]] && if ! rmdir ${NEW_ROOT}    >/dev/null; then do_error "Error: could not remove '${NEW_ROOT}'"; fi
[[ -d ${NEW_OVERLAY} ]] && if ! rmdir ${NEW_OVERLAY} >/dev/null; then do_error "Error: could not remove '${NEW_OVERLAY}'"; fi

if [[ "$OPT" == "init" ]]; then # checking & installing required packages for init process
  do_update_repositories
  do_install coreutils-stty
  ${LOCAL_BACKUP} || do_install netcat
  do_init
fi

pre_proc

do_exec mount -t overlay -o noatime,lowerdir=${LOWER_NAME}/,upperdir=${NEW_OVERLAY}/upper,workdir=${NEW_OVERLAY}/work ram-root ${NEW_ROOT}

do_exec mkdir -p ${NEW_ROOT}${OLD_ROOT}
do_exec mount -o bind / ${NEW_ROOT}${OLD_ROOT}
do_exec mount -o noatime,nodiratime,move /proc ${NEW_ROOT}/proc
do_exec pivot_root ${NEW_ROOT} ${NEW_ROOT}${OLD_ROOT}
for dir in /dev /sys /tmp; do do_exec mount -o noatime,nodiratime,move ${OLD_ROOT}${dir} ${dir}; done
do_exec mount -o noatime,nodiratime,move ${NEW_OVERLAY} /overlay

post_proc

__beep
do_logger "Info: *** Pivot-root successful ***"

exit 0
