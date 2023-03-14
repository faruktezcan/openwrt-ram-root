function debug
{
    echo "#############|  Entering DEBUG mode  |############";
    local cmd=""
    while [[ "$cmd" != "exit" ]]
    do
        read -p "> " cmd
        case "$cmd" in
            exit ) ;;
            * ) eval "$cmd" ;;
        esac
    done
    echo "#############|  End of DEBUG mode |############";
}
