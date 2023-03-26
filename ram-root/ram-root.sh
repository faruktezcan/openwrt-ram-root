#!/bin/ash

#set -u

#set -xv # debug

# Performs ext-root from ram drive as PIVOT root
# By Faruk Tezcan  'tezcan.faruk@gmail.com'



__list_contains() { # return 0 if $1 contains $2; otherwise return 1
  [[ "${1%% ${2} *}" == "${1}" ]] && return 1
  return 0
}

#__list_contains() { # return 0 if $1 contains $2; otherwise return 1
#  local T="${1/${2}/}"
#  [[ ${#T} -eq ${#1} ]] && return 1
#  return 0
#}

__occurs() { # check if $1 (separated with $3) contains $2 & return the # of occurances
  echo "${1}" | tr {{"${3:-" "}"}} {{'\n'}} | grep -F -c -x "${2}"
}

__lowercase() { # converts $1 to lowercase & if $2 defined, set $2 as a variable with result
  local __resultvar=${2}
  local __result=$(echo "${1}" | awk '{print tolower($0)}')
  [[ "$__resultvar" ]] && eval $__resultvar="'$__result'" || echo -n "$__result"
}

__identity_file() { # list identity file(s)
  find /etc/dropbear/dropbear_* | while read -r name; do echo -n "-i ${name} "; done
}

__wait_for_network() { # wait until local network is ready up to NETWORK_WAIT_TIME
  ubus -t ${NETWORK_WAIT_TIME} wait_for network 2>/dev/null
}

__printf() { # formatted numeric output
  [[ -z "${1}" ]] && { echo "Empty value!"; return 1; }

  if [[ ${1} =~ ^[+-]?[0-9]+$ ]]; then # "Integer!"
    echo ${1} | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta'
  elif [[ ${1} =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then # "Float!"
    echo "$( echo ${1} | cut -d'.', -f1 | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta' ).$(echo $1 | cut -d'.', -f2)"
  else # Mixed
    echo ${1} | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta'
  fi
}

__beep() {
  ${VERBOSE} && echo -e "\a"
}

do_exec() { # <command> execute command(s)
  local cmd="${@}"
  do_logger "Info: executing < ${cmd} >"
  eval "${cmd}" || do_error "Error: command failed. Return code: $?"
}

do_logger() { # <msg> $1-log messssage
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
  ${VERBOSE} && {
    echo -e "\aram-root: Notice: rebooting in $secs seconds\nPress 'Ctrl+C' to cancel"
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
}

do_rm() { # remove dir or file(s)
  do_exec rm -Rf ${@}
}

do_mklink() { # make symlink $1-file/dir $2-destination
  [[ -L ${2} ]] || do_exec ln -sf ${1} ${2}
}

do_pidmsg() { # wait until given pid job is completed $1-pid#  2-backup name
  while [[ $(ps | awk '{print $1}' | grep -c ${1}) -gt 0 ]]; do sleep 1; done
  do_logger "Info: backup created in ${2}"
}

do_backup() { # create ram-root backup
  local dir="/overlay/upper/"
  local tar_cmd="nice -n 19 tar -C ${dir} ${EXCL} ${INCL} -czf - ."

  local free_memory=$( grep -i 'MemAvailable' /proc/meminfo | awk '{print $2*1024}' )
  do_logger "Info: available memory = $( __printf ${free_memory} ) bytes"

  do_logger "Info: calculating backup size"
  local pv_cmd=""
  ${VERBOSE} && { ${PV_INSTALLED} && pv_cmd="pv -tb |" || start_progress; }
  local backup_size=$( eval "${tar_cmd} | ${pv_cmd} wc -c" )
  ${VERBOSE} && { ${PV_INSTALLED} || kill_progress; }
  do_logger "Notice: backup size = $( __printf ${backup_size} ) bytes"

  if ${LOCAL_BACKUP}; then
    local share=${LOCAL_BACKUP_SHARE}
    mkdir -p ${share}
    local server_free_space=$( df -kP ${share} | awk '$1 != "Filesystem" {print $4*1024}' )
  else
    local share=${SHARE}
    server_free_space=$( ${SSH_CMD} "mkdir -p ${share}; df -kP ${share}" | awk '$1 != "Filesystem" {print $4*1024}' )
  fi
  do_logger "Notice: ${SERVER} free space = $( __printf ${server_free_space} ) bytes"

  [[ ${backup_size} -gt ${server_free_space} ]] && do_error "Error: backup size too big"

  local name="${share}/${BACKUP_FILE}"
  local mv_cmd="[[ -f ${name} ]] && mv -f ${name} ${name}~"
  pv_cmd=""
  ${VERBOSE} && ! ${BACKGROUND_BACKUP} && ${PV_INSTALLED} && pv_cmd="pv -eps ${backup_size} |"

  ${LOCAL_BACKUP} \
    && local cmd="${tar_cmd} | ${pv_cmd} cat > ${name}" \
    || local cmd="${tar_cmd} | ${pv_cmd} ${SSH_CMD} \"${mv_cmd}; cat > ${name}\""

  if ${BACKGROUND_BACKUP}; then
    do_logger "Info: running in background"
    eval "${cmd}" &
    do_pidmsg $! "${SERVER}:${name}" &
  else
    do_logger "Info: sending backup file"
    eval "${cmd}"
    do_logger "Info: created in ${SERVER}:${name}"
  fi # BACKGROUND_BACKUP
}

do_restore() { # restore ram-root backup
  local name="${SHARE}/${BACKUP_FILE}"
  local tar_cmd="nice -n 19 tar -C ${NEW_OVERLAY}/upper/ -xf"

  case ${OPT} in
    start)
      local backupExist=false
      ${LOCAL_BACKUP} \
        && { [[ -f ${name} ]] && backupExist=true; } \
        || { ${SSH_CMD} "[[ -f ${name} ]] && return 0 || return 1" && backupExist=true; }

      if ${backupExist}; then
        do_logger "Info: restoring file '${name}' from ${SERVER}"

        ${LOCAL_BACKUP} \
          && local cmd="${tar_cmd} ${name}" \
          || local cmd="${SSH_CMD} \"gzip -dc ${name}\" | ${tar_cmd} -"

        ${VERBOSE} && start_progress
        eval "${cmd}"
        ${VERBOSE} && kill_progress
      else
        do_logger "Notice: backup file '${name}' not found"
      fi
      ;;

    reset)
      do_logger "Info: bypassing backup file '${name}'"
      ;;
  esac
}

do_chkconnection() { # check internet connection $1-seconds(default=60) $2-do_error (default Y)
  __wait_for_network

  ${LOCAL_BACKUP} && return 0

  local secs=${1:-60}
  local err=${2:-Y}

  do_logger "Info: verifying connection to '${SERVER}' port '${PORT}'"
  while [[ ${secs} -gt 0 ]]
  do
    ${SSH_CMD} 'exit 0' 2>\dev\null & return 0
    ${VERBOSE} && printf "\a\r%2d" ${secs}
    secs=$(( ${secs}-1 ))
    sleep 1
  done
  local msg="Error: connection lost to server '${SERVER}' port '${PORT}'"
  [[ "${err}" == "Y" ]] && do_error "${msg}"
  do_logger ${msg}
  return 1
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
    [[ -f ${key_file} ]] || {
      do_exec dropbearkey -t ${key_type} -f ${key_file}
      do_mklink ${key_file} /root/.ssh/id_${key_type}
      #do_mklink ${key_file} /root/.ssh/id_dropbear
    }
    local key=$(dropbearkey -y -f ${key_file} | grep "ssh-")
    local name=$(echo ${key} | awk '{print $3}')
    local cmd="mkdir -p ${SHARE}; \
               touch /etc/dropbear/authorized_keys; \
               sed -i '/${key_type}/ s/${name}/!@@@!/' /etc/dropbear/authorized_keys; \
               sed -i '/^$/d; /!@@@!/d' /etc/dropbear/authorized_keys; \
               echo ${key} >> /etc/dropbear/authorized_keys"
    ${SSH_CMD} "${cmd}" || do_error "Error: server '${SERVER}' setup not completed. Return code: $?"
  done

  do_mklink /ram-root/init.d/ram-root /etc/init.d
  name="/root/.profile"
  touch ${name}
  sed -i '/^$/d; /shell_prompt/d' ${name}
  echo -e "\n. /ram-root/shell_prompt\n" >> ${name}
}

do_pre_proc_packages() { # install non-backable, non-preserved packages after reboots
  [[ -z "${PACKAGES}" ]] && return 0

  LOWER_NAME="${NEW_OVERLAY}/lower:"
  do_exec mkdir -p ${NEW_OVERLAY}/lower
  mkdir -p ${NEW_OVERLAY}/lower/usr/lib/opkg
  tar -C /usr/lib/opkg -cf - . | tar -C ${NEW_OVERLAY}/lower/usr/lib/opkg -xf -
  cp -f /etc/opkg.conf /tmp/opkg_ram-root.conf
  echo "dest ram-root ${NEW_OVERLAY}/lower" >> /tmp/opkg_ram-root.conf
  do_update_repositories
  do_logger "Info: installing package(s) -> ${PACKAGES}"
  for name in ${PACKAGES}; do do_install ${name} "/tmp/opkg_ram-root.conf" "ram-root"; done
  rm -f /tmp/opkg_ram-root.conf
}

do_update_repositories() {
  type opkg_update >/dev/null || source /ram-root/functions/opkgupdate.sh
  opkg_update ${INTERACTIVE}; [[ $? -gt 0 ]] && do_error "Error: updating repository failed"
}

do_install() { # install a package $1-package nsme $2-config_file(default=/etc/opkg.conf) $3-destination(default=root)
  if [[ -n "${name}" ]]; then
    local name=${1}
    local conf_file=${2:-"/etc/opkg.conf"}
    local dest_name=${3:-"root"}

    [[ -n "$(opkg status ${name})" ]] && { do_logger "Notice: '${name}' already installed"; return; }
    [[ -z "$(opkg find ${name})" ]] && do_error "Error: '${name}' not found"
    do_exec opkg install -f ${conf_file} -d ${dest_name} ${name}
  fi
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
} # pre_proc

###################################
#     POST INSTALL PROCEDURE      #
###################################
post_proc() {
  local message_diplayed=false
  ls -1A /etc/rc.d | grep ^S | grep -v ram-root | while read name
  do
    [[ -f ${OLD_ROOT}/etc/rc.d/${name} ]] || {
      ${message_diplayed} || { do_logger "Info: starting service(s) enabled in 'ram-root'"; message_diplayed=true; }
      do_exec /etc/init.d/${name:3} start
    }
  done

  message_diplayed=false
  ls -1A ${OLD_ROOT}/etc/rc.d | grep ^S | grep -v ram-root | while read name
  do
    [[ -f /etc/rc.d/${name} ]] || {
      ${message_diplayed} || { do_logger "Info: stopping service(s) disabled in 'ram-root'"; message_diplayed=true; }
      do_exec /etc/init.d/${name:3} stop
    }
  done

  [[ -n "${START_SERVICES}" ]] && {
    do_logger "Info: starting service(s) defined in '${CONFIG_NAME}'"
    for name in ${START_SERVICES}
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} start || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "${RESTART_SERVICES}" ]] && {
    do_logger "Info: re-starting service(s) defined in '${CONFIG_NAME}'"
    for name in ${RESTART_SERVICES}
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} restart || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "${STOP_SERVICES}" ]] && {
    do_logger "Info: stopping service(s) defined in ${CONFIG_NAME}'"
    for name in ${STOP_SERVICES}
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} stop || do_logger "Notice: ${name} not found"
    done
  }

  [[ -f ${RCLOCAL_FILE} ]] && do_exec sh ${RCLOCAL_FILE}
  [[ $(ls -1A /etc/rc.d | grep -c "S??uhttpd") -gt 0 ]] && do_exec /etc/init.d/uhttpd restart
  do_rm ${NEW_ROOT} ${NEW_OVERLAY} ${RAM_ROOT} /rom /tmp/root /tmp/ram-root.failsafe # some cleanup
  do_mklink ${OLD_ROOT}${RAM_ROOT} /

  echo "PIVOT" > /tmp/ram-root-active

 # ${VERBOSE} && echo -e "\aram-root: Notice: re-connect to the router after ${NETWORK_WAIT_TIME} seconds if your console does not respond"
 # do_exec /etc/init.d/network restart
 # do_chkconnection ${NETWORK_WAIT_TIME}

} # post_proc

###################################
#             MAIN                #
###################################
#trap "exit 1" INT TERM
#trap "kill 0" EXIT

# BASE="${0##*}"

[[ $# -ne 1 ]] && { do_logger "Error: need an option to run"; exit 1; }

OPT=$(__lowercase ${1})

OLD_ROOT="/old_root"
RAM_ROOT="/ram-root"
NEW_ROOT="/tmp/root"
NEW_OVERLAY="/tmp/overlay"

CONFIG_NAME="ram-root.cfg"
[[ -f ${RAM_ROOT}/${CONFIG_NAME} ]] || { do_logger "Error: config file '${RAM_ROOT}/${CONFIG_NAME}' not exist"; exit 1; }
source ${RAM_ROOT}/${CONFIG_NAME}

${DEBUG} && set -xv

${INTERACTIVE_UPGRADE} && INTERACTIVE="-i"

if [[ -f /tmp/ram-root.failsafe ]]; then
  do_rm /etc/rc.d/???ram-root
  do_logger "Info: previous attempt was not successful"
  do_logger "      fix the problem & run 'rm /tmp/ram-root.failsafe' command to continue"
  [[ -z "${PS1}" ]] && exit 1

  type ask_bool >/dev/null || source /ram-root/functions/askbool.sh
  ask_bool ${INTERACTIVE} -t 5 -d N "\a\nDo you want to remove it now" && {
    if umount ${NEW_OVERLAY} >/dev/null; then
      do_rm /tmp/ram-root.failsafe
    else
      do_logger "Error: removing 'ram-root' files was unsuccesful. Please reboot"
    fi
  }
  exit 1
fi

eval $(grep -e 'VERSION=\|BUILD_ID=' /usr/lib/os-release)
SYSTEM_IP=$(ifconfig br-lan | grep "inet addr" | cut -f2 -d':' | cut -f1 -d' ')
LOCAL_BACKUP=false
[[ $(__occurs "$(__lowercase ${HOSTNAME}) ${SYSTEM_IP} localhost 127.0.0.1" $(__lowercase ${SERVER}) ) -gt 0 ]] && { SERVER=${SYSTEM_IP}; LOCAL_BACKUP=true; }
SHARE="${SHARE}/${HOSTNAME}"
LOCAL_BACKUP_SHARE="${SHARE}"
[[ ${LOCAL_BACKUP} && $(__occurs ${SHARE} ${OLD_ROOT}) -eq 0 ]] && LOCAL_BACKUP_SHARE="${OLD_ROOT}${SHARE}" # make sure backup goes to < OLD-ROOT >
SERVER_SHARE="${SERVER}:${SHARE}"
BACKUP_FILE="${BUILD_ID}.tar.gz"
SSH_CMD="nice -n 19 ssh -qy $(__identity_file) ${USER}@${SERVER}/${PORT}"
#SCP_CMD="scp -q -p $(__identity_file) -P ${PORT}"


which pv >/dev/null && PV_INSTALLED=true || PV_INSTALLED=false

[[ -f ${EXCLUDE_FILE} && $(wc -c ${EXCLUDE_FILE} | cut -f1 -d' ') -gt 0 ]] && EXCL="-X ${EXCLUDE_FILE}"
[[ -f ${INCLUDE_FILE} && $(wc -c ${INCLUDE_FILE} | cut -f1 -d' ') -gt 0 ]] && INCL="-T ${INCLUDE_FILE}"
[[ -z "${PS1}" ]] && VERBOSE=false
[[ "${OPT}" == "init" && -n "${PS1}" ]] && VERBOSE=true

if ${VERBOSE}; then
  type print_progress >/dev/null || source /ram-root/functions/printprogress.sh
  STDERR="-s"
fi

if [[ ! -f /tmp/ram-root-active ]]; then
  [[ $(__occurs "stop backup upgrade" $OPT) -gt 0 ]] && { do_logger "Info: 'ram-root' not running"; exit 1; }
else
  [[ $(__occurs "init start reset" $OPT) -gt 0 ]] && { do_logger "Info: 'ram-root' already running"; exit 1; }
fi

[[ -d ${NEW_ROOT}    ]] && if ! rmdir ${NEW_ROOT}    >/dev/null; then do_error "Error: could not remove '${NEW_ROOT}'"; fi
[[ -d ${NEW_OVERLAY} ]] && if ! rmdir ${NEW_OVERLAY} >/dev/null; then do_error "Error: could not remove '${NEW_OVERLAY}'"; fi

case ${OPT} in
  start)
    pre_proc
    ${BACKUP} && do_restore
    ;;

  reset)
    pre_proc
    do_logger "Info: bypassing backup file"
    ;;

  init)
    do_update_repositories
    for name in coreutils-sleep coreutils-sort coreutils-stty pv; do do_install ${name}; done
    do_init
    pre_proc
    ${BACKUP} && do_backup
    ;;

  backup)
    ${BACKUP} || { do_logger "Info: backup option is not selected"; exit 1; }
    if do_chkconnection ${NETWORK_WAIT_TIME} "N"; then
      do_backup
      __beep
      exit 0
    else
      do_logger "Error: no response from server '${SERVER}' port '${PORT}'"
      __beep
      exit 1
    fi
    ;;

  stop)
    if ${BACKUP}; then
      if do_chkconnection ${NETWORK_WAIT_TIME} "N"; then
        do_backup
      else
        do_logger "Error: no response from server '${SERVER}' port '${PORT}'"
      fi
    fi
    __beep
    do_error "Rebooting" 10
    ;;

  upgrade)
    ${RAM_ROOT}/tools/opkgupgrade.sh -i
    exit 0
    ;;

  *)
    do_logger "Error: invalid option: '${OPT}'"
    exit 1
    ;;
esac

do_exec mount -t overlay -o noatime,lowerdir=${LOWER_NAME}/,upperdir=${NEW_OVERLAY}/upper,workdir=${NEW_OVERLAY}/work ram-root ${NEW_ROOT}
do_exec mkdir -p ${NEW_ROOT}${OLD_ROOT}
do_exec mount -o bind / ${NEW_ROOT}${OLD_ROOT}
do_exec mount -o noatime,nodiratime,move /proc ${NEW_ROOT}/proc
do_exec pivot_root ${NEW_ROOT} ${NEW_ROOT}${OLD_ROOT}
for dir in /dev /sys /tmp; do do_exec mount -o noatime,nodiratime,move ${OLD_ROOT}${dir} ${dir}; done
do_exec mount -o noatime,nodiratime,move ${NEW_OVERLAY} /overlay

post_proc

do_logger "Info: ram-root successful"
__beep
cd /

exit 0
