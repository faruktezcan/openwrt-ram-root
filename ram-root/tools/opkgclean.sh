#!/bin/ash

#set -x

#takes one argument/parameter: the name of the package which didn't install correctly and should be removed along with its dependencies
#example: sh ./opkclean.sh <pacakge-name>

type print_progress &>/dev/null || source /ram-root/functions/printprogress.sh

if [ $# -ne 1 ]; then # HELP
    echo "Syntax: $(basename ${0}) <packagename>"
    echo "  Cleans up after failed install of <packagename>"
    exit 1
fi

echo -e "\nCleaning '$1' debris"
echo -e "PLease wait...\n"

start_progress

fname=mktemp

for i in $(opkg --force-reinstall --force-space --noaction install $1 | grep https:// | cut -f 2 -d ' '); do
  wget -qO- ${i} | tar -Oxz ./data.tar.gz | tar -tz  | sed -e 's/^./\/overlay\/upper/' >> ${fname}
done

kill_progress

for f in $(cat ${fname} | sort -ru); do
  if [ -f $f -o -L $f ]; then
     echo "Removing file '$f'"
     rm -f $f
     deleted=1
  else
    if [ -d $f ]; then
      if [ -n "$(ls -A $f)" ]; then
        echo "Not removing directory '$f' -  not empty"
      else
        rmdir $f
      fi
    fi
  fi
done

rm ${fname}

[ $deleted -eq 1 ] && echo -e "\nYou may need to reboot for the free space to become visible"
