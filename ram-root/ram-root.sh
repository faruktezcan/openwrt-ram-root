#!/bin/sh
#set -xv # debug

# Performs ext-root from ram drive as PIVOT root
# By Faruk Tezcan  "tezcan.faruk@gmail.com"

do_exec() { # <command> executes a command
  local cmd="${@}"
  do_logger "Info: processing command < ${cmd} >"
  eval ${cmd} || do_error "Error: command failed. Return code: $?"
}

do_logger() { # log msg
  local stderr
  [[ "$VERBOSE" == "Y" ]] && stderr="-s"
  logger ${stderr} -p info -t ram-root "$1"
}

do_error() { # <error message> <seconds> $1-mesage text $2-seconds(default=30)
  local secs=${2:-30}
  local name="/etc/rc.d/???ram-root"
  [ -f $name ] && rm $name # remove autostart
  name="${OLD_ROOT}${name}"
  [ -f $name ] && rm $name # remove autostart

  do_logger "$1"
  do_logger "Error: stopping 'ram-root' process"
  [[ $(__occurs "init backup" $OPT) -gt 0 ]] && exit 1
  sync
  [ "$VERBOSE" == "Y" ] && { echo -e "\a\nRebooting in $secs seconds\nPress 'Ctrl+C' to cancel"; do_countdown $secs; echo -ne "\a"; }
  reboot &
  sleep 30
  reboot -f &
  exit 1
}

do_countdown() { # <seconds> $1-seconds(default=60)
  local secs=${1:-60}
  while [ ${secs} -gt 0 ]
  do
    printf "\r%2d" $secs
    let secs--
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

do_pidmsg() { # waits until given pid job is completed $1-pid #
  while [[ $(ps | awk '{print $1}' | grep -c ${1}) -gt 0 ]]; do sleep 1; done
  [[ "$VERBOSE" == "Y" ]] && echo -ne "\a"
  do_logger "Info: backup finished"
}

do_backup() { # creates ram-root backup
  local dir="/overlay/upper/"
  local backup_size=$(du -cs $dir | grep total | awk '{print $1*1024}')
  local share=${SHARE}
  local server_free_space

  do_logger "Info: backup file size = ${backup_size} bytes"

  if ( ${LOCAL_BACKUP} ); then
    share=${BACKUP_SHARE}
    [[ -d ${share} ]] || mkdir -p ${share}
    server_free_space=$(df -kP ${share} | awk '$1 != "Filesystem" {print $4*1024}')
  else
    server_free_space=$(${SSH_CMD} "[[ -d ${share} ]] || mkdir -p ${share}; df -kP ${share}" | awk '$1 != "Filesystem" {print $4*1024}')
  fi
 
  do_logger "Info: server ${SERVER} free space = ${server_free_space} bytes"

  if [[ $server_free_space -gt $backup_size ]]; then
    local nc="nice -n 19"
    local name="${share}/${BACKUP_FILE}.gz"
    local cmd="mkdir -p ${share}; [[ -f ${name} ]] && mv -f ${name} ${name}.~"
    if ( ${LOCAL_BACKUP} ); then
      eval ${cmd}
      ${nc} tar -C $dir $EXCL $INCL -c -z -f ${name} . & >/dev/null
    else
      ${nc} tar -C $dir $EXCL $INCL -c -f - . | ${nc} ${SSH_CMD} "${cmd}; ${nc} gzip > ${name}" & >/dev/null
    fi
    do_pidmsg $! &
    do_logger "Info: backup is running in background & will be created shortly"
    [[ "$VERBOSE" == "Y" ]] && echo -ne "\a"
  else
    do_error "Error: backup file size is too big"
  fi
}

do_chkconnection() { # checks internet connection $1-seconds(default=60) $2-do_error (default Y)
  if ( ${LOCAL_BACKUP} ); then return 0; fi
  
  if which netcat >/dev/null; then
    __wait_for_network
    local secs=${1:-60}
    local msg=$secs
    while [[ $secs -gt 0 ]]
    do
      [[ $msg -eq $secs ]] && do_logger "Info: checking connection on server '$SERVER' port '$PORT'"
      netcat -w 1 -z $SERVER $PORT >/dev/null && return 0
      [ "$VERBOSE" == "Y" ] && printf "\a\r%2d" $secs
      let secs--
    done
    echo
    local msg="Error: connection lost to server '$SERVER' port '$PORT'"
    [[ "$2" != "N" ]] && do_error "$msg"
    do_logger "$msg"
    return 1
  else
    do_error "'netcat' package must be installed"
  fi
}

do_init() { # server setup
  case $VERSION in
    1* ) local key_type="rsa";;
    *  ) local key_type="ed25519"
         if ( ${LOCAL_BACKUP} ); then
           eval SERVER_$(${SSH_CMD} "grep -e 'VERSION=' /usr/lib/os-release")
           case $SERVER_VERSION in
             1* ) local key_type="rsa";;
           esac
         fi
         ;;
  esac

  local key_file="/etc/dropbear/dropbear_${key_type}_host_key"

  do_logger "Info: setting up 'local system'"
  mkdir -p /root/.ssh
  [[ -f $key_file ]] || do_exec dropbearkey -t $key_type -f $key_file
  do_mklink $key_file /root/.ssh/id_${key_type}
  do_mklink $key_file /root/.ssh/id_dropbear

  local key=$(dropbearkey -y -f $key_file | grep "ssh-")
  local name=$(echo $key | awk '{print $3}')
  local msg="Error: server '$SERVER' setup not completed. Return code: "
  local cmd="mkdir -p $SHARE; \
             touch /etc/dropbear/authorized_keys; \
             sed -i '/${name}/d' /etc/dropbear/authorized_keys; \
             echo $key >> /etc/dropbear/authorized_keys"
  if ( ${LOCAL_BACKUP} ); then
    eval ${cmd}
  else
    do_logger "Info: setting up server '$SERVER'"
    ${SSH_CMD} "${cmd}" || do_error "$msg $?"
  fi
}

do_pre_install_packages() { # installs non-backable, non-preserved packages after reboots
  do_logger "Info: installing package(s)- ${PACKAGES}"
  cp -f /etc/opkg.conf /tmp/opkg_ram-root.conf
  echo "dest ram-root ${PKGS_DIR}" >> /tmp/opkg_ram-root.conf
  do_update_repositories
  for name in ${PACKAGES}
  do
    do_install ${name} "/tmp/opkg_ram-root.conf" "ram-root"
  done
  rm -f /tmp/opkg_ram-root.conf
}

do_update_repositories() {
  type opkg_update >/dev/null || source /ram-root/functions/opkgupdate.sh
  opkg_update $INTERACTIVE; [[ $? -gt 0 ]] && do_error "Error: updating repository failed"
}

do_install() { # installs a package $1-list of packages $2-config_file(default=/etc/opkg.conf) $3-destination(default=root)
  local name=${1}
  local conf_file=${2:-"/etc/opkg.conf"}
  local dest_name=${3:-"root"}

  [[ -n "$(opkg status $name)" ]] && { do_logger "Notice: '$name' already installed"; return; }
  [[ -z "$(opkg find $name)" ]] && do_error "Error: '$name' not found"
  do_exec opkg install -f ${conf_file} -d ${dest_name} $name
}

__list_contains() { # returns 1 if $1 contains $2
    local var="$1"
    local str="$2"
    local val

    eval "val=\"\${var}\""
    [[ "${val%% $str *}" == "$val" ]] && return 1 || return 0
}

__occurs() { # check if $1 (separated with $3) contains $2 & return the # of occurances
  echo "${1}" | tr {{"${3:-" "}"}} {{'\n'}} | grep -F -c -x ${2}
}

__lowercase() { # converts $1 to lowercase & sets $2 as a variable with result if $2 defined
  local __resultvar=${2}
  local __result=$(echo ${1} | awk '{print tolower($0)}')
  [[ "$__resultvar" ]] && eval $__resultvar="'$__result'" || echo -n "$__result"
}

__identity_file() { # lists identity file(s)
  ls -1 /etc/dropbear/dropbear_* | while read name; do echo -n "-i ${name} "; done
}

__wait_for_network() { # waits until local network is ready up to NETWORK_WAIT_TIME
  ubus -t ${NETWORK_WAIT_TIME} wait_for network 2>/dev/null
}


###################################
#       PRE INSTALL PROCEDURE     #
###################################
pre_proc() {
  do_rm /tmp/ram-root-active
  touch /tmp/ram-root.failsafe

  [[ "${OPT}" == "init" ]] && {
    do_mklink /ram-root/init.d/ram-root /etc/init.d
    local name="/root/.profile"
    touch ${name}
    sed -i '/shell_prompt/d' ${name}
    echo -e "\n. /ram-root/shell_prompt" >> $name
  }

  mkdir -p $NEW_OVERLAY
  do_logger "Info: creating ram disk"
  do_exec mount -t tmpfs -o rw,nosuid,nodev,noatime tmpfs $NEW_OVERLAY
  mkdir -p ${NEW_ROOT} ${PKGS_DIR} ${NEW_OVERLAY}/upper ${NEW_OVERLAY}/work

  [[ -n "${PACKAGES}" ]] && do_pre_install_packages

  if [[ "$BACKUP" == "Y" ]]; then
    if ( ${LOCAL_BACKUP} ); then
      local name="${RESTORE_SHARE}/${BACKUP_FILE}.gz"
    else
      local name="${SHARE}/${BACKUP_FILE}.gz"
    fi
    local backupExist="false"

    case $OPT in
      start)
        if ( ${LOCAL_BACKUP} ); then
          [[ -f ${name} ]] && backupExist="true"
        else
          if ( ${SSH_CMD} "[ -f ${name} ] && return 0 || return 1" ); then backupExist="true"; fi
        fi

        if [[ "${backupExist}" == "true" ]]; then
          do_logger "Info: restoring ram-root backup '${name}'"
          [[ "$VERBOSE" == "Y" ]] && start_progress
          if ( ${LOCAL_BACKUP} ); then
            do_exec tar -C ${NEW_OVERLAY}/upper/ -x -z -f ${name}
          else
            do_exec ${SSH_CMD} "gzip -dc ${name}" | tar -C ${NEW_OVERLAY}/upper/ -x -f -
          fi
          [ "$VERBOSE" == "Y" ] && kill_progress
        else
          do_logger "Info: backup file '${name}' not found"
        fi
        ;;
      reset)
        do_logger "Info: bypassing backup file '${name}'"
        ;;
    esac
  fi

} # pre_proc

###################################
#     POST INSTALL PROCEDURE      #
###################################
post_proc() {
  do_exec /etc/init.d/network restart

  [ "$VERBOSE" == "Y" ] && echo -e "\a\nInfo: *** Re-connect to the router after ${NETWORK_WAIT_TIME} seconds if your console does not respond ***"
  do_chkconnection ${NETWORK_WAIT_TIME}

  local ft=""
  ls -1A /etc/rc.d | grep ^S | grep -v ram-root | while read name
  do
    [[ -f ${OLD_ROOT}/etc/rc.d/${name} ]] || {
      [[ -z $ft ]] && { do_logger "Info: starting services enabled in 'ram-root'"; ft="Y"; }
      do_exec /etc/init.d/${name:3} start
    }
  done

  ft=""
  ls -1A ${OLD_ROOT}/etc/rc.d | grep ^S | grep -v ram-root | while read name
  do
    [[ -f /etc/rc.d/${name} ]] || {
      [[ -z $ft ]] && { do_logger "Info: stopping services disabled in 'ram-root'"; ft="Y"; }
      do_exec /etc/init.d/${name:3} stop
    }
  done

  [[ -n "$START_SERVICES" ]] && {
    do_logger "Info: starting service(s) in '$CONFIG_NAME'"
    for name in $START_SERVICES
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} start || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "$RESTART_SERVICES" ]] && {
    do_logger "Info: re-starting service(s) in '$CONFIG_NAME'"
    for name in $RESTART_SERVICES
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} restart || do_logger "Notice: ${name} not found"
    done
  }

  [[ -n "$STOP_SERVICES" ]] && {
    do_logger "Info: stopping service(s) in $CONFIG_NAME'"
    for name in $STOP_SERVICES
    do
      [[ -f /etc/init.d/${name} ]] && do_exec /etc/init.d/${name} stop || do_logger "Notice: ${name} not found"
    done
  }

  [[ -f ${RCLOCAL_FILE} ]] && do_exec sh ${RCLOCAL_FILE}

  [[ $(ls -1A /etc/rc.d | grep -c "S??uhttpd") -gt 0 ]] && do_exec /etc/init.d/uhttpd restart
  [[ -f /etc/init.d/zram ]] && if /etc/init.d/zram enabled; then sync; do_exec /etc/init.d/zram restart; fi

  sync

# some cleanup
  do_rm /tmp/ram-root.failsafe ${NEW_ROOT} ${NEW_OVERLAY} ${RAM_ROOT} /rom
  do_mklink ${OLD_ROOT}${RAM_ROOT} /

  echo "PIVOT" > /tmp/ram-root-active
} # post_proc

###################################
#             MAIN                #
###################################
#trap "exit 1" INT TERM
#trap "kill 0" EXIT

# BASE="${0##*}"

OPT=${1}
[[ $# -ne 1 ]] && { do_logger "Error: need an option to run"; exit 1; }

OLD_ROOT="/old_root"
RAM_ROOT="/ram-root"

CONFIG_NAME="ram-root.cfg"
[[ -f ${RAM_ROOT}/${CONFIG_NAME} ]] || { do_logger "Error: config file '${RAM_ROOT}/$CONFIG_NAME' not exist"; exit 1; }
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
  [[ -z "$PS1" ]] && exit 1
  type ask_bool >/dev/null || source /ram-root/functions/askbool.sh
  ask_bool $INTERACTIVE -t 5 -d N "\a\nDo you want to remove it now" && do_rm /tmp/ram-root.failsafe
  exit 1
fi

LOCAL_BACKUP=false
#SYSTEM_IP=$(uci get network.lan.ipaddr)
SYSTEM_IP=$(ifconfig br-lan | grep "inet addr" | cut -f2 -d':' | cut -f1 -d' ')
if [[ $(__occurs "$(__lowercase ${HOSTNAME}) ${SYSTEM_IP} localhost 127.0.0.1" $(__lowercase ${SERVER}) ) -gt 0 ]]; then
  SERVER=${SYSTEM_IP}
  LOCAL_BACKUP=true
fi

BACKUP_SHARE=${SHARE}
RESTORE_SHARE=${SHARE}

if ( ${LOCAL_BACKUP} ); then 
  [[ $(__occurs $(__lowercase ${SHARE}) ${OLD_ROOT}) -eq 0 ]] && BACKUP_SHARE="${OLD_ROOT}/${SHARE}" # make sure backup goes to < OLD-ROOT >
fi

SHARE="${SHARE}/${HOSTNAME}"
SERVER_SHARE="${SERVER}:${SHARE}"
NEW_ROOT="/tmp/root"
NEW_OVERLAY="/tmp/overlay"
PKGS_DIR="${NEW_OVERLAY}/lower"
BACKUP_FILE="${BUILD_ID}.tar"
SSH_CMD="ssh $(__identity_file) ${USER}@${SERVER}/${PORT}"

[[ -f $EXCLUDE_FILE && $(wc -c $EXCLUDE_FILE | awk {'print $1'}) -gt 0 ]] && EXCL="-X $EXCLUDE_FILE"
[[ -f $INCLUDE_FILE && $(wc -c $INCLUDE_FILE | awk {'print $1'}) -gt 0 ]] && INCL="-T $INCLUDE_FILE"

[[ -z "$PS1" ]] && VERBOSE="N"
[[ "$OPT" == "init" && -n "$PS1" ]] && VERBOSE="Y"
[[ $VERBOSE == "Y" ]] && { type print_progress >/dev/null || source /ram-root/functions/printprogress.sh; }

case $OPT in
  init|start|reset) ;;
  backup|stop)
    [[ -f /tmp/ram-root-active ]] || { do_logger "Info: 'ram-root' not running"; exit 1; }
    [[ $BACKUP == "Y" ]] || do_logger "Info: backup option is not selected" && {
      do_chkconnection 60 "N" && {
        do_backup
        sync
        [[ "${OPT}" == "stop" ]] && do_error "Rebooting" 5
        exit 0
      }
      do_logger "Info: no response from server '$SERVER' port '$PORT'"
    }
    [[ "${OPT}" == "stop" ]] && do_error "Rebooting" 5
    exit 1
    ;;
  upgrade) ${RAM_ROOT}/tools/opkgupgrade.sh -i; exit 0 ;;
  *) do_logger "Info: invalid option: '${OPT}'"; exit 1 ;;
esac

[[ -d $NEW_ROOT    ]] && if ! rmdir $NEW_ROOT    >/dev/null; then do_error "Error: could not remove '$NEW_ROOT'"; fi
[[ -d $NEW_OVERLAY ]] && if ! rmdir $NEW_OVERLAY >/dev/null; then do_error "Error: could not remove '$NEW_OVERLAY'"; fi

if [[ "$OPT" == "init" ]]; then # checking & installing required packages for init process
    do_update_repositories
    do_install coreutils-stty
    [[ ${SYSTEM_IP} != ${SERVER} ]] && do_install netcat
    do_init
fi

pre_proc

if [[ -z "${PACKAGES}" ]]; then
  do_exec mount -t overlay -o noatime,lowerdir=/,upperdir=${NEW_OVERLAY}/upper,workdir=${NEW_OVERLAY}/work ram-root $NEW_ROOT
else
  do_exec mount -t overlay -o noatime,lowerdir=${PKGS_DIR}:/,upperdir=${NEW_OVERLAY}/upper,workdir=${NEW_OVERLAY}/work ram-root $NEW_ROOT
fi
mkdir -p ${NEW_ROOT}${OLD_ROOT}
do_exec mount -o bind / ${NEW_ROOT}${OLD_ROOT}
do_exec mount -o noatime,nodiratime,move /proc ${NEW_ROOT}/proc
do_exec pivot_root $NEW_ROOT ${NEW_ROOT}${OLD_ROOT}
for dir in /dev /sys /tmp
do
  do_exec mount -o noatime,nodiratime,move ${OLD_ROOT}${dir} ${dir}
done
do_exec mount -o noatime,nodiratime,move $NEW_OVERLAY /overlay

post_proc

[[ "$VERBOSE" == "Y" ]] && echo -ne "\a"
do_logger "Info: *** Pivot-root successful ***"

[[ $BACKUP == "Y" && $OPT == "init" ]] && do_backup # 1st backup

exit 0