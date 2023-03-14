type sleep_ms &>/dev/null || source /ram-root/functions/sleepms.sh

print_progress() { # Print progress indicator

# $(head -30 /dev/urandom | tr -dc "0123456789" | head -c$x) random $x digit numbers between 0-9
# local type=${1:-$(head -30 /dev/urandom | tr -dc "123456" | head -d)} # random 1 digit numbers between 1-6
  local type=${1:-$(awk 'BEGIN{srand(); print int(rand()*6)+1}')} # random 1 digit numbers between 1-6
  local _RED_="\e[1;31m" _RST_="\e[0m"
  local a b seq i

#  type=6

  case $type in
  1|2 )
    [[ $type -eq 1 ]] && a="|/-\\" || a=".oOo. "; seq=$(seq 0 $((${#a}-1)))
    while :
    do
      for i in $seq; do echo -en "\r$_RED_ ${a:$i:1} $_RST_"; sleep_ms 20; done
    done
  ;;
  3 )
    a="     ---->"; seq=$(seq ${#a} -1 0)
    b="     <----"; local seq1=$(seq 0 ${#b})
    while :
    do
      for i in $seq;  do echo -en "\r$_RED_${a:$i:5}$_RST_";  sleep_ms 20; done
      for i in $seq1; do echo -en "\r$_RED_${b:$i:5}$_RST_ "; sleep_ms 20; done
    done
  ;;
  4 )
    a="Please wait!... "; seq=$(seq 0 ${#a})
    while :
    do
      for i in $seq; do echo -en "\r$_RED_${a:0:$i}$_RST_"; sleep_ms 20; done
      sleep_ms 20
      for i in $seq; do echo -en "\b\b "; sleep_ms 10; done
      sleep_ms 50
    done
  ;;
  5 )
    seq=$(seq 0 10)
    while :
    do
      for i in $seq; do echo -en "$_RED_>$_RST_"; sleep_ms 10; done
      printf "\r\e[K"
      sleep_ms 50
    done
  ;;
  6 )
    a=".oOo."; seq=$(seq 0 ${#a})
    while :
    do
      for i in $seq; do echo -en "\r$_RED_${a:0:$i}$_RST_"; sleep_ms 20; done
      printf "\r"
      for i in $seq; do printf " "; sleep_ms 20; done
    done
  ;;
  * )
    while :
    do
      echo -en "$_RED_?$_RST_"; sleep 3s
    done
  ;;
  esac
}

start_progress() { # Start print_progress() process
  printf "\e[?25l"
  print_progress $1 &
  progress_pid=$!
  export progress_pid
  trap kill_progress_and_exit HUP INT TERM # Catch a Ctl-C
  return 0
}

kill_progress() { # Stop current print_progress() process
  kill -9 $progress_pid
  wait $progress_pid 2>/dev/null
  export -n progress_pid
  printf "\r\e[K\e[0m\e[?25h"
  return 0
}

kill_progress_and_exit() { # Stop current print_progress() process and exit
  kill_progress
  echo -e "\a\nStopped!\n"
  exit 1
}
