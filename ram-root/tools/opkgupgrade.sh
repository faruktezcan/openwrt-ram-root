#!/bin/sh
#takes one argument/parameter: < -i > for interactive upgrade
#example: opkgupgrade.sh [-i]

# set -x

type opkg_update &>/dev/null || source /ram-root/functions/opkgupdate.sh
type ask_bool &>/dev/null || source /ram-root/functions/askbool.sh
type print_progress &>/dev/null || source /ram-root/functions/printprogress.sh
#type debug &>/dev/null || source /ram-root/functions/debug.sh

error() {
  echo -e "\a"
  cat <<EOF
Usage: $(basename ${0}) [-i]

Upgrades 'opkg' packages

    -i Interactive upgrade mode

EOF
  exit 1
}

trap "exit 1" INT TERM HUP

_COL_GRN="\e[32m"
_COL_BLU="\e[34m"
_COL_RED="\e[31m"
_COL_RST="\e[0m"

NAME_WIDTH=30
COLUMN_WIDTH=80
which stty > /dev/null && COLUMN_WIDTH=$(stty size | awk '{print $2}') # pkg name = 'coreutils-stty'
let COLUMN_COUNT=$COLUMN_WIDTH/$(($NAME_WIDTH+3))
[[ $COLUMN_COUNT -eq 0 ]] && COLUMN_COUNT=1

if [[ $# -eq 0 ]]; then
  INTERACTIVE=""
  DEFAULT="y"
elif [[ $# -eq 1 ]]; then
  [[ "$1" != "-i" ]] && error
  INTERACTIVE="-i"
  DEFAULT="n"
else
  error
fi

opkg_update $INTERACTIVE; [[ $? -ne 0 ]] && { echo "Package repository update failed"; exit 1; }

echo -e "\a\e[1mChecking${_COL_RST}\n"
start_progress
list="$(opkg list-upgradable | sort | awk '{print $1}')"
kill_progress
[[ -z "$list" ]] && { echo -e "\a\n\e[1;5;31mNo package(s) to upgrade${_COL_RST}\n"; exit 1; }

#debug

echo -e "\a${_COL_GRN}Upgradable package(s):${_COL_RST}\n"
i=0
for name in $list; do
  printf "| %-${NAME_WIDTH}s " ${name:0:$NAME_WIDTH}
  let i++
  [[ $(($i%$COLUMN_COUNT)) -eq 0 ]] && printf "\n"
done
echo -e "\n\n"

ask_bool $INTERACTIVE -t 10 -d $DEFAULT "${_COL_RED}\aDo you want to continue${_COL_RST}" || { echo -e "\n"; exit 0; }

for name in $list; do
  ask_bool $INTERACTIVE -d $DEFAULT "\nUpgrade ${_COL_BLU}${name}${_COL_RST}" && { opkg upgrade $name; [[ $? -ne 0 ]] && exit 1; }
done

exit 0
