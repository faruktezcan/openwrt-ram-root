ask_bool_help() {
  cat <<EOF
Usage: ask_bool [-i] [-d arg] [-t arg] [-h] prompt

    -i Interactive upgrade mode
    -d Default answer (y/n)
    -t Default response time (sec.)
    -h Help text

EOF
}

ask_bool() {
  local i answer
  local interactive="n"
  local default="n"
  local timeout=5

  while getopts ":id:t:h" flag; do
    case $flag in
      i ) interactive="y" ;;
      d ) default=$OPTARG ;;
      t ) timeout=$OPTARG ;;
      h ) ask_bool_help; return 1 ;;
      : ) echo -e "\aMissing argument: -$OPTARG requires an argument"; ask_bool_help; return 1 ;;
      * ) echo -e "\a$0: Unrecognized option: $1"; ask_bool_help; return 1 ;;
    esac
  done
  shift $(($OPTIND-1)) # Discard the options

  [[ $timeout -le 00 ]] && timeout=05
  [[ $timeout -gt 60 ]] && timeout=60

  [[ "$interactive" = "y" ]] && [[ "$default" != "n" ]] && default="y" || [[ "$default" != "y" ]] && default="n"
  answer=$default

  if [[ "$interactive" = "y" ]]; then
    answer=""

    case $default in
      y|Y ) echo -en "$* (\e[1;4mY\e[0m/n)?:   " ;;
      *   ) echo -en "$* (y/\e[1;4mN\e[0m)?:   " ;;
    esac

    for i in $(seq $timeout -1 0); do
      printf "\b\b%2d" $i
      read -s -n 1 -t 1 answer
      [[ "$answer" != "" ]] && { printf "\b\b %s" $answer; break; }
    done

    case $answer in
      y|Y|n|N ) ;;
      * ) answer=$default; printf "\b\b %s" $answer ;;
    esac

    echo -e "\n"
  fi

  [[ $answer = "y" || $answer = "Y" ]]
}
