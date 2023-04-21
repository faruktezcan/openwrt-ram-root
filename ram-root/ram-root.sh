#!/bin/sh

# Performs ext-root from ram drive as PIVOT root
# By Faruk Tezcan  'tezcan.faruk@gmail.com'

#set -u
#set -xv # debug

#__list_contains() { # return 0 if $1 contains $2; otherwise return 1
#  local T="${1/${2}/}"
#  [[ ${#T} -eq ${#1} ]] && return 1
#  return 0
#}

__valid_ip() {
  local ip=${1}
  if [[ $( echo ${ip} | grep -c . ) -gt 0 ]] ; then
    [[ "$ip" == "$(echo ${ip} | grep -E '(([0-9]{1,3})\.){3}([0-9]{1,3}){1}' | \
      grep -vE '25[6-9]|2[6-9][0-9]|[3-9][0-9][0-9]')" ]] && return 0
    return 1
  fi
  return 0
}

__list_contains() { # return 0 if $1 contains $2; otherwise return 1
  [[ "${1%% ${2} *}" == "${1}" ]] && return 1 || return 0
}

__occurs() { # check if $1 (separated with $3) contains $2 & return the # of occurances
  echo "${1}" | tr {{"${3:-" "}"}} {{'\n'}} | grep -F -c -x "${2}"
}

__lowercase() { # converts $1 to lowercase & if $2 defined, set $2 as a variable with result
  local __resultvar="${2}"
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
  [[ -z "${1}" ]] && { echo 0; return 1; }

  if [[ ${1} =~ ^[+-]?[0-9]+$ ]]; then # "Integer"
    echo ${1} | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta'
  elif [[ ${1} =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then # "Float"
    echo "$( echo ${1} | cut -d'.', -f1 | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta' ).$(echo $1 | cut -d'.', -f2)"
  else # Mixed
    echo ${1} | sed ':a; s/\b\([0-9]\+\)\([0-9]\{3\}\)\b/\1,\2/; ta'
  fi
  return 0
}

__beep() {
  ${VERBOSE} && echo -ne "\a"
}

__get_mem() {
  local line
  while read -r line; do case "${line}" in Mem${1}:*) set $line; echo $(( ${2} * 1024 )); break;; esac; done </proc/meminfo
}

__which() {
  which "${1}" &>/dev/null && return 0 || return 1
}

do_exec() { # <command> execute command(s)
  local cmd="${@}"

  do_logger "Info: executing < ${cmd} >"
  eval "${cmd}" || do_error "Error: command failed. Return code: '$?'"
}

do_logger() { # <msg> $1-log messssage
  logger ${STDERR} -p info -t ram-root "${1}"
}

do_error() { # <error message> <seconds> $1-mesage text $2-seconds(default=30)
  [[ "${1}" != " " ]] && do_logger "${1}"

  do_logger "Error: stopping 'ram-root' process"
  [[ $(__occurs "backup upgrade" ${OPT}) -gt 0 ]] && exit 1

  local secs=${2:-30}
  local name="/etc/rc.d/???ram-root"

  ${VERBOSE} && { echo "ram-root: Notice: rebooting in $secs seconds\nPress 'Ctrl+C' to cancel"; do_countdown ${secs}; }

  reboot &
  sleep 30
  __beep
#  reboot -f &
  echo 1 > /proc/sys/kernel/sysrq
  echo b > /proc/sysrq-trigger
  exit 1
}

do_countdown() { # <seconds> $1-seconds(default=60)
  local secs=${1:-60}

  while [ ${secs} -gt 0 ]; do
    printf "\a\r%2d" ${secs}
    secs=$((secs-1))
    sleep 1
  done
}

do_rm() { # remove dir or file(s)
  do_exec rm -Rf "${@}"
}

do_mklink() { # make symlink $1-file/dir $2-destination
  [[ -h ${2} ]] || do_exec ln -sf ${1} ${2}
}

do_backup() { # create ram-root backup
  local dir="/overlay/upper/"
  local tar_cmd="nice -n 19 tar -C ${dir} ${EXCL} ${INCL} -cf - ."

  do_logger "Info: available memory = $( __printf $(__get_mem Available) ) bytes"
  do_logger "Info: calculating backup size"
  local pv_cmd=""
  ${VERBOSE} && { ${PV_INSTALLED} && pv_cmd=" pv -tb |" || start_progress; }
  local backup_tar_size=$( eval "${tar_cmd} | wc -c" )
  local backup_zip_size=$( eval "${tar_cmd} -z |${pv_cmd} wc -c" )
  ${VERBOSE} && { ${PV_INSTALLED} || kill_progress; }
  do_logger "Notice: backup size = $( __printf ${backup_zip_size} ) bytes"

  if ${LOCAL_BACKUP}; then
    local backup_size=${backup_zip_size}
    local share=${LOCAL_BACKUP_SHARE}
    mkdir -p ${share}
    local server_free_space=$( df ${share} | awk '$1 != "Filesystem" {print $4*1024}' )
  else
    local backup_size=${backup_tar_size}
    local share=${SHARE}
    local server_free_space=$( ${SSH_CMD} "mkdir -p ${share}; df ${share}" | awk '$1 != "Filesystem" {print $4*1024}' )
  fi
  do_logger "Notice: ${SERVER} free space = $( __printf ${server_free_space} ) bytes"

  [[ ${backup_zip_size} -gt ${server_free_space} ]] && do_error "Error: backup size too big"

  local name="${share}/${BACKUP_FILE}"
  local mv_cmd="[[ -f ${name} ]] && mv -f ${name} ${name}~"
  pv_cmd=""
  ${VERBOSE} && ${PV_INSTALLED} && ! ${BACKGROUND_BACKUP} && pv_cmd=" pv -eps ${backup_size} |"

  ${LOCAL_BACKUP} \
    && local cmd="${tar_cmd} -z |${pv_cmd} cat > ${name}" \
    || local cmd="${tar_cmd} |${pv_cmd} ${SSH_CMD} '${mv_cmd}; gzip > ${name}'"

  if ${BACKGROUND_BACKUP}; then
    do_logger "Info: running in background"
    eval "${cmd}; do_logger 'Info: backup created in ${SERVER}:${name}'" &
  else
    do_logger "Info: sending backup file"
    eval "${cmd}; do_logger 'Info: backup created in ${SERVER}:${name}'"
  fi
} # do_backup

do_restore() { # restore ram-root backup
  local name="${SHARE}/${BACKUP_FILE}"
  local tar_cmd="nice -n 19 tar -C ${NEW_OVERLAY}/upper/ -xf"
  local backupExist=false

  ${LOCAL_BACKUP} \
  && { [[ -f ${name} ]] && backupExist=true; } \
  || { ${SSH_CMD} "[[ -f ${name} ]] && return 0 || return 1" && backupExist=true; }

  if ${backupExist}; then
    do_logger "Info: restoring file '${name}' from '${SERVER}'"
    ${VERBOSE} && start_progress

    ${LOCAL_BACKUP} \
      && eval "${tar_cmd} ${name}" -z \
      || eval "${SSH_CMD} 'gzip -dc ${name}' | ${tar_cmd} -"

    ${VERBOSE} && kill_progress
  else
    do_logger "Notice: backup file '${name}' not found"
  fi
} # do_restore

do_chkconnection() { # check internet connection $1-seconds(default=60) $2-do_error (default Y)
  __wait_for_network

  ${LOCAL_BACKUP} && return 0

  local secs=${1:-60}
  local err=${2:-Y}

  do_logger "Info: verifying connection to '${SERVER}' port '${PORT}'"
  while [[ ${secs} -gt 0 ]]; do
    ${SSH_CMD} 'exit 0' 2>/dev/null && { printf "\r"; return 0; }
    ${VERBOSE} && printf "\a\r%2d" ${secs}
    secs=$((secs-1))
    sleep 1
  done

  printf "\a\r"
  local msg="Error: connection failed"
  [[ "${err}" == "Y" ]] && do_error "${msg}"
  do_logger "${msg}"
  __beep
  return 1
} # do_chkconnection

do_init() { # server setup
  do_logger "Info: setting up first time"

  do_mklink /ram-root/init.d/ram-root /etc/init.d
  name="/root/.profile"
  touch ${name}
  sed -i '/^$/d; /shell_prompt/d' ${name}
  echo -e "\nsource /ram-root/shell_prompt\n" >> ${name}

  if ${BACKUP}; then
    if ${LOCAL_BACKUP}; then
      mkdir -p ${SHARE}
    else
      for key_file in $(ls /etc/dropbear/dropbear_*_host_key); do
        key_type=$(echo $key_file | cut -d _ -f 2)
        do_mklink ${key_file} /root/.ssh/id_${key_type}
        local key=$(dropbearkey -y -f ${key_file} | grep "ssh-")
        local name=$(echo ${key} | awk '{print $3}')
        local cmd="\
          mkdir -p ${SHARE}; \
          touch /etc/dropbear/authorized_keys; \
          sed -i '/${key_type}/ s/${name}/!@@@!/' /etc/dropbear/authorized_keys; \
          sed -i '/^$/d; /!@@@!/d' /etc/dropbear/authorized_keys; \
          echo ${key} >> /etc/dropbear/authorized_keys"
        ${SSH_CMD} "${cmd}" || do_error "Error: server '${SERVER}' setup not completed. Return code: '$?'"
      done
    fi
  fi
} # do_init

do_update_repositories() {
  type opkg_update >/dev/null || source /ram-root/functions/opkgupdate.sh
  opkg_update ${INTERACTIVE} || do_error "Error: updating repository failed"
  opkg list | cut -d' ' -f1 > /tmp/available.packages
}

do_chk_packages() {
  local pkgs
  for name in ${@}; do
    [[ -f /usr/lib/opkg/info/${name}.control ]] && { do_logger "Notice: '${name}' already installed"; continue; }
    [[ $( grep -cw ^${name}$ /tmp/available.packages ) -eq 0 ]] && { do_logger "Notice: '${name}' not found"; continue; }
    pkgs="${pkgs} ${name}"
  done
  echo "${pkgs}"
}

do_install() { # install package(s)
  local packages="$( do_chk_packages ${@} )"
  [[ -z "${packages}" ]] && return 1
  do_exec opkg install ${packages}
  return 0
}

do_create_chroot_cmd() {
  local packages="$( do_chk_packages ${PRE_PACKAGES} )"
  [[ -z "${packages}" ]] && return 1

  cat << EOF > /tmp/pre_proc_pkgs.sh
#!/bin/sh
opkg install ${packages}
exit $?
EOF
  chmod +x /tmp/pre_proc_pkgs.sh
  return 0
}

do_pre_packages() { # install non-backable, non-preserved packages after reboots
  do_update_repositories
  do_logger "Info: installing 'PRE_PACKAGES'"
  if do_create_chroot_cmd; then
    local lower_dir="${NEW_OVERLAY}/lower"
    local pre_dir="${NEW_OVERLAY}/pre"
    mkdir -p ${lower_dir} ${pre_dir}/upper ${pre_dir}/work
    mount -t overlay -o noatime,lowerdir=/,upperdir=${pre_dir}/upper,workdir=${pre_dir}/work ram-root_pre ${lower_dir} \
      || do_error "Error: < pre packages mount overlay > code $?"
    for dir in /proc /dev /sys /tmp; do mount -o rbind ${dir} ${lower_dir}${dir} \
      || do_error "Error: < pre packages mount sys dirs > code $?"; done
    chroot ${lower_dir} "/tmp/pre_proc_pkgs.sh"
#      || do_error "Error: < pre packages chroot > code $?"
    umount $( mount | grep ${lower_dir} | cut -f3 -d' ' | sort -r ) \
      || do_error "Error: < pre packages umount sys dirs > code $?"
    tar -C ${pre_dir}/upper/ -cf - . | tar -C ${lower_dir} -xf -
    rm -Rf ${pre_dir} /tmp/pre_proc_pkgs.sh
    LOWER_NAME="${lower_dir}:"
  fi
}

###################################
#       PRE INSTALL PROCEDURE     #
###################################
do_pre_pivot_root() {
  do_logger "Info: creating ram disk"

  do_exec touch /tmp/ram-root.failsafe
  do_exec mkdir -p ${NEW_ROOT} ${NEW_OVERLAY}

  if [[ -f /sys/class/zram-control/hot_add ]] && __which mkfs.ext4; then
    ZRAM_ID=$(cat /sys/class/zram-control/hot_add)
    local zram_comp_algo="$( uci -q get system.@system[0].zram_comp_algo )"
    [[ -z "$zram_comp_algo" ]] && zram_comp_algo="lzo"
    if [[ $(grep -c "$zram_comp_algo" /sys/block/zram${ZRAM_ID}/comp_algorithm) -gt 0 ]]; then
      echo ${zram_comp_algo} > /sys/block/zram${ZRAM_ID}/comp_algorithm
      echo $(( $(__get_mem Total) / 2 )) > /sys/block/zram${ZRAM_ID}/disksize
      mkfs.ext4 -O ^has_journal,fast_commit /dev/zram${ZRAM_ID} &>/dev/null \
        && ZRAM_EXIST=true \
        || { do_logger "Notice: could not create 'ext4' filesystem on 'zram${ZRAM_ID}'"
             echo ${ZRAM_ID} > /sys/class/zram-control/hot_remove; }
    else
      do_logger "Notice: compression algorithm '${zram_comp_algo}' is not supported for 'zram${ZRAM_ID}'"
    fi
  fi

  if ${ZRAM_EXIST}; then
    do_logger "Info: mounting 'ext4' ram drive"
    do_exec mount -t ext4 -o noatime,nobarrier,discard /dev/zram${ZRAM_ID} ${NEW_OVERLAY}
    FILE_SYSTEM="zram${ZRAM_DEV}"
  else
    do_logger "Info: mounting 'tmpfs' ram drive"
    do_exec mount -t tmpfs -o noatime tmpfs ${NEW_OVERLAY}
    FILE_SYSTEM="tmpfs"
  fi

  do_exec mkdir -p ${NEW_OVERLAY}/upper ${NEW_OVERLAY}/work

  [[ -n "${PRE_PACKAGES}" ]] && do_pre_packages

} # do_pre_pivot_root

###################################
#     POST INSTALL PROCEDURE      #
###################################
do_post_pivot_root() {
  do_exec mount -t overlay -o noatime,lowerdir=${LOWER_NAME}/,upperdir=${NEW_OVERLAY}/upper,workdir=${NEW_OVERLAY}/work ram-root ${NEW_ROOT}
  do_exec mkdir -p ${NEW_ROOT}${OLD_ROOT}
  do_exec mount -o bind / ${NEW_ROOT}${OLD_ROOT}
  do_exec mount -o noatime,nodiratime,move /proc ${NEW_ROOT}/proc
  do_exec pivot_root ${NEW_ROOT} ${NEW_ROOT}${OLD_ROOT}
  for dir in /dev /sys /tmp; do do_exec mount -o noatime,nodiratime,move ${OLD_ROOT}${dir} ${dir}; done
  do_exec mount -o noatime,nodiratime,move ${NEW_OVERLAY} /overlay

  do_chkconnection

  local message_diplayed=false
  ls -1A /etc/rc.d | grep ^S | grep -v ram-root | while read -r name; do
    [[ -f ${OLD_ROOT}/etc/rc.d/${name} ]] || {
      ${message_diplayed} || { do_logger "Info: starting service(s) enabled in 'ram-root'"; message_diplayed=true; }
      do_exec /etc/init.d/${name:3} start
    }
  done

  message_diplayed=false
  ls -1A ${OLD_ROOT}/etc/rc.d | grep ^S | grep -v ram-root | while read -r name; do
    [[ -f /etc/rc.d/${name} ]] || {
      ${message_diplayed} || { do_logger "Info: stopping service(s) disabled in 'ram-root'"; message_diplayed=true; }
      do_exec /etc/init.d/${name:3} stop
    }
  done

  [[ -n "${START_SERVICES}" ]] && {
    do_logger "Info: starting service(s) defined in '${CONFIG_NAME}'"
    for name in ${START_SERVICES}; do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} start || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "${RESTART_SERVICES}" ]] && {
    do_logger "Info: re-starting service(s) defined in '${CONFIG_NAME}'"
    for name in ${RESTART_SERVICES}; do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} restart || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "${STOP_SERVICES}" ]] && {
    do_logger "Info: stopping service(s) defined in ${CONFIG_NAME}'"
    for name in ${STOP_SERVICES}; do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} stop || do_logger "Notice: ${name} not found"
    done
  }

  [[ -f ${RC_LOCAL_FILE} ]] && do_exec sh ${RC_LOCAL_FILE}

  if ${ZRAM_EXIST}; then
    __which fstrim && do_exec fstrim /overlay
    echo 1 > /sys/block/zram${ZRAM_ID}/compact
    ${VERBOSE} && zram-status ${ZRAM_ID}
  fi

  do_rm ${NEW_ROOT} ${NEW_OVERLAY} /ram-root /rom /tmp/available.packages /tmp/ram-root.failsafe
  do_mklink ${OLD_ROOT}/ram-root /

  echo "PIVOT_ROOT" > /tmp/ram-root-active
} # do_post_pivot_root

##################
#      MAIN      #
##################

#echo $(__get_mem Total)

#trap "exit 1" INT TERM
#trap "kill 0" EXIT

# BASE="${0##*}"

[[ $# -ne 1 ]] && { do_logger "Error: need an option to run"; exit 1; }
OPT=$(__lowercase ${1})
NEW_ROOT="/tmp/root"
OLD_ROOT="/old_root"
NEW_OVERLAY="/tmp/overlay"
CONFIG_NAME="ram-root.cfg"

[[ -f /ram-root/${CONFIG_NAME} ]] || { do_logger "Error: config file '/ram-root/${CONFIG_NAME}' not exist"; exit 1; }
source /ram-root/${CONFIG_NAME}

${DEBUG} && set -xv

${INTERACTIVE_UPGRADE} && INTERACTIVE="-i"

if [[ -f /tmp/ram-root.failsafe ]]; then
  do_rm /etc/rc.d/???ram-root
  do_logger "Info: previous attempt was not successful"
  do_logger "fix the problem & run 'rm /tmp/ram-root.failsafe' command to continue"
  [[ -z "${PS1}" ]] && exit 1

  type ask_bool >/dev/null || source /ram-root/functions/askbool.sh
  ask_bool ${INTERACTIVE} -t 5 -d N "\a\nDo you want to remove it now" && {
    [[ -d ${NEW_OVERLAY} ]] && if ! umount ${NEW_OVERLAY} >/dev/null; then
      do_logger "Error: removing 'ram-root' files was unsuccesful. Please reboot"
    fi
  }
  exit 1
fi

[[ -d ${NEW_ROOT} ]] && do_rm ${NEW_ROOT}
[[ -d ${NEW_OVERLAY} ]] && do_rm ${NEW_OVERLAY}

eval $(grep -e 'VERSION=\|BUILD_ID=' /usr/lib/os-release)
SYSTEM_IP=$(ifconfig br-lan | grep "inet addr" | cut -f2 -d':' | cut -f1 -d' ')
LOCAL_BACKUP=false
ZRAM_EXIST=false
[[ $(__occurs "$(__lowercase ${HOSTNAME}) ${SYSTEM_IP} localhost 127.0.0.1" $(__lowercase ${SERVER}) ) -gt 0 ]] && { SERVER=${SYSTEM_IP}; LOCAL_BACKUP=true; }
SHARE="${SHARE}/${HOSTNAME}"
LOCAL_BACKUP_SHARE="${SHARE}"
[[ ${LOCAL_BACKUP} && $(__occurs ${SHARE} ${OLD_ROOT}) -eq 0 ]] && LOCAL_BACKUP_SHARE="${OLD_ROOT}${SHARE}" # make sure backup goes to < OLD-ROOT >
BACKUP_FILE="${BUILD_ID}.tar.gz"
SSH_CMD="nice -n 19 ssh -q -y $(__identity_file) ${USER}@${SERVER}/${PORT}"
#SCP_CMD="nice -n scp -q -p $(__identity_file) -P ${PORT}"
__which pv && PV_INSTALLED=true || PV_INSTALLED=false
[[ -f ${EXCLUDE_FILE} ]] && EXCL="-X ${EXCLUDE_FILE}"
[[ -f ${INCLUDE_FILE} ]] && INCL="-T ${INCLUDE_FILE}"
[[ -z "${PS1}" ]] && VERBOSE=false
[[ "${OPT}" == "init" && -n "${PS1}" ]] && VERBOSE=true

if ${VERBOSE}; then
  type print_progress >/dev/null || source /ram-root/functions/printprogress.sh
  STDERR="-s"
fi

if [[ -f /tmp/ram-root-active ]]; then
  [[ $(__occurs "init start reset" $OPT) -gt 0 ]] && { do_logger "Info: 'ram-root' already running"; exit 1; }
else
  [[ $(__occurs "stop backup upgrade" $OPT) -gt 0 ]] && { do_logger "Info: 'ram-root' not running"; exit 1; }
fi

__valid_ip ${SERVER} || { do_logger "Error: '${SERVER}' not a valid ip"; exit 1; }

case ${OPT} in
  init)
    # If the packages < e2fsprogs kmod-fs-ext4 kmod-zram > are installed before running ram-root,
    # the ram device will be stored on a zram disk which uses approximately half the memory compared to < tmpfs >.
    # This means that you can have twice the disk capacity while consuming the same amount of memory.

    do_chkconnection 30 N || exit 1
    if [[ -n "${INIT_PACKAGES}" ]]; then
      do_update_repositories
      do_logger "Info: installing 'INIT_PACKAGES'"
      do_install ${INIT_PACKAGES}
      do_init
    fi
    do_pre_pivot_root
    do_post_pivot_root
    ${BACKUP} && do_backup
    do_logger "Info: ram-root started first time using '${FILE_SYSTEM}'"
    ;;

  start)
    do_chkconnection 30 N || exit 1
    do_pre_pivot_root
    ${BACKUP} && do_restore
    do_post_pivot_root
    do_logger "Info: ram-root started using '${FILE_SYSTEM}'"
    ;;

  reset)
    do_chkconnection 30 N || exit 1
    do_pre_pivot_root
    do_post_pivot_root
    cmd="Info: ram-root started using '${FILE_SYSTEM}'"
    ${BACKUP} && cmd="${cmd} - bypassed backup"
    do_logger "${cmd}"
    ;;

  stop)
    ${VERBOSE} && {
      type ask_bool &>/dev/null || source /ram-root/functions/askbool.sh
      ask_bool -i -t 10 -d n "\a\e[31mAre you sure\e[0m" || exit 1
      ${BACKUP} && if ask_bool -i -t 10 -d n "\a\e[31mDo you want to backup before rebooting\e[0m"; then
        do_chkconnection 30 N && do_backup
      fi
    }
    do_error " " 5
    ;;

  backup)
    ${BACKUP} || { do_error "Info: backup not defined in config file"; __beep; exit 1; }
    do_chkconnection 5 N && do_backup
    ;;

  upgrade)
    ${VERBOSE} && {
      ask_bool -i -t 10 -d n "\a\e[31mAre you sure\e[0m" || exit 1
      do_chkconnection 5 N || exit 1
      type ask_bool &>/dev/null || source /ram-root/functions/askbool.sh
      /ram-root/tools/opkgupgrade.sh ${INTERACTIVE}
      ${BACKUP} && ask_bool -i -t 10 -d n "\a\e[31mDo you want to backup now\e[0m" && do_backup
      exit 0
    }
    do_error "Error: cannot upgrade in background"
   __beep
    exit 1
    ;;

  *)
    do_logger "Error: invalid option: '${OPT}'"
    __beep
    exit 1
    ;;
esac

exit 0
