#!/bin/sh

#set -x

type opkg_update &>/dev/null || source /ram-root/functions/opkgupdate.sh
type print_progress &>/dev/null || source /ram-root/functions/printprogress.sh

do_backup() {
  [ "$cmd" != "" ] && {
    rm -f $FILENAME 1>/dev/null 2>&1
    touch $FILENAME 1>/dev/null 2>&1 || { echo "Invalid file name: '${FILENAME}'"; rm -f ${FILENAME} 1>/dev/null 2>&1; exit 1; }
  }
  echo -e "\nChecking. Please wait!\n"
  opkg_update -i;  opkg list | cut -d' ' -f1 > /tmp/available.packages
 
  start_progress

  local ft=$(mktemp); local ft1=$(mktemp); local COUNT1=0; local COUNT2=0; local ov_control

  for NAME in $(find /overlay/upper/usr/lib/opkg/info -name "*.control" 2>/dev/null | sed 's/.*\///;s/.control//' | sort -r); do
    [[ ! -f $ROM/usr/lib/opkg/info/$NAME.control && $( grep -cw ^${NAME}$ /tmp/available.packages ) -gt 0 ]] && ov_control="$NAME $ov_control"
  done

  for NAME in $ov_control; do
    cat /usr/lib/opkg/info/$NAME.control | grep -e Depends: | sed -e 's/Depends: //' >> $ft1
  done
  cat $ft1 | tr ', ' '\n' | sort -u - > $ft

  for NAME in $ov_control; do
    if [[ $(grep -c $NAME $ft) -eq 0 ]]; then
      [[ $COUNT1 -eq 0 ]] && echo -e "\r\e[K\nPackage(s):"
      let COUNT1++
      printf "\r\e[K%3d %s\n" $COUNT1 $NAME
      [ "$cmd" != "" ] && echo $NAME >> $FILENAME
    fi
  done
  rm -f $ft $ft1  1>/dev/null 2>&1

  for NAME in $(ls -1A /etc/init.d); do
    local rcd="S??$NAME"
    local ft=""
    if [[ -e /etc/rc.d/$rcd ]]; then
      [[ -e $ROM/etc/rc.d/$rcd ]] || ft='+'
    else
      [[ -e $ROM/etc/rc.d/$rcd ]] && ft='-'
    fi
    if [[ -n "$ft" ]]; then
      [[ $COUNT2 -eq 0 ]] && echo -e "\r\e[K\nService(s):"
      let COUNT2++
      printf "\r\e[K%3d %s%s\n" $COUNT2 $ft $NAME
      [ "$cmd" != "" ] &&echo "$ft$NAME" >> $FILENAME
    fi
  done

  kill_progress
  echo

  if [[ $COUNT1 -eq 0 && $COUNT2 -eq 0 ]]; then
    echo -e "\nNo user installed package(s) and/or service(s) found"
    exit 1
  fi

  rm /tmp/available.packages

  [ "$cmd" == "" ] && exit 0

  echo -e "\n'$FILENAME' created. If you keep your settings during the firmware"
  echo -e "upgrade process, you will have it after the upgrade."
  echo -e "\nOtherwise, you should save this file now, then finish your"
  echo -e "firmware upgrade and restore '$FILENAME'."
  echo -e "\nEnter '$(basename "$0") restore' command to reinstall user-installed package(s) and/or service(s)."
  exit 0
} # do_backup

do_restore() {
  [[ -e $FILENAME ]] || { echo -e  "\a\n'${FILENAME}' not found"; exit 1; }
  [[ -z "$(cat $FILENAME)" ]] && { echo -e "\a\nNo user installed package(s) and/or service(s) found"; exit 1; }
  opkg_update -i
  local MSG="Restoring user-installed package(s)"
  echo -e "\a\n$MSG\n"
  echo $MSG > $FILENAME.log

  for NAME in $(cat $FILENAME | grep -v "^[+-]"); do
    MSG="already installed"
    if [[ ! -e /usr/lib/opkg/info/$NAME.control ]]; then
      MSG="not found"
      if [[ -n "$(opkg info $NAME)" ]]; then
        opkg install $NAME; [[ $? -eq 0 ]] && MSG="installed" || MSG="Error! Code:$?"
      fi
    fi
    echo "$NAME > $MSG"
    echo "$NAME > $MSG" >> $FILENAME.log
  done
  echo >> $FILENAME.log

  MSG="Restoring service(s)"
  echo -e "\n$MSG\n"
  echo $MSG >> $FILENAME.log

  for NAME in $(cat $FILENAME | grep "^[+-]"); do
    local CONT=${NAME:0:1}
    local NAME=${NAME:1}
    local xx="/etc/init.d/$NAME"
    MSG="not found"
    if [[ -e $xx ]]; then
      case $CONT in
        + )
          MSG="already enabled"
          [[ ! -e /etc/rc.d/S??$NAME ]] && { $xx start; $xx enable; [ $? -eq 0 ] && MSG="enabled" || MSG="Error! Code:$?"; }
          ;;
        - )
          MSG="already disabled"
          [[ -e /etc/rc.d/S??$NAME ]] && { $xx stop; $xx disable; [ $? -eq 0 ] && MSG="disabled" || MSG="Error! Code:$?"; }
          ;;
        * )
          MSG="$CONT undefined"
          ;;
      esac
    fi
    echo "${NAME} > ${MSG}"
    echo "${NAME} > ${MSG}" >> $FILENAME.log
  done

  echo -e "\a\nAll the package(s) and/or service(s) in $FILENAME restored"
  echo -e "\nPlease check '$FILENAME.log' and restart the router"
  exit 0

} # do_restore

usage() {
cat <<EOF

Usage: $(basename "$0") [OPTION(S)]...[backup|restore]
where: -f < file name > to save package name(s)
                default='/etc/config/overlaypkgs.lst'
       -d       debug option
       -h       show this help text

Backup user installed package(s) and/or service(s) before firmware upgrade and restore them later

EOF

exit 1
} # usage

#[[ $# -eq 0 ]] && usage

ROM="$(cat /proc/mounts | grep /dev/root | awk '{print $2}')"
FILENAME="/etc/config/overlaypkgs.lst"
cmd=""

while getopts ':df:h' flag
do
  case $flag in
    d    ) set -x ;;
    f    ) FILENAME=$OPTARG ;;
    \?   ) echo "Invalid option: -$OPTARG"; usage ;;
    :    ) echo "Invalid option: -$OPTARG requires an argument"; usage ;;
    h\?* ) usage ;;
  esac
done

shift $((OPTIND-1)) # Discard the options and sentinel --
[[ $# -gt 1 ]] && usage
cmd=$1
shift

case $cmd in
  ""|backup  ) do_backup ;;
  restore ) do_restore ;;
  *       ) echo "Invalid option: -$cmd"; usage ;;
esac

exit 0
