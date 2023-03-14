#!/bin/ash

type opkg_update &>/dev/null || source /ram-root/functions/opkgupdate.sh
type print_progress &>/dev/null || source /ram-root/functions/printprogress.sh

getdeps () {
    # grab the "Depends:" line of "opkg info", remove the leading word,
    # and delete commas giving a space-separated list:
    echo "$(opkg info ${1} | grep "^Depends:" | cut -d " " -f 2- | tr -d ",")"
}

if [ $# -ne 1 ]
then
    # HELP:
    echo "Syntax: $(basename ${0}) <packagename>"
    echo "  Shows the dependencies of <packagename> and their sizes"
    exit 1
fi

echo -e "\aThis script is VERY SLOW!!!\n"

opkg_update -i

start_progress 4

package="${1}"
deps=""
newdeps="$(getdeps "${package}")"

while [ "${deps}" != "${newdeps}" ]
do
    # Given a list of packages, go through them and determine
    # their dependencies.  Add those to the existing list of
    # dependencies.  Rinse and repeat until the list stops
    # changing.
    deps="${newdeps}"
    deplist="${newdeps}"
    for dep in ${newdeps}
    do
        add="$(getdeps "${dep}")"
        deplist=$(echo ${deplist} ${add})
    done
    # Turn it into a newline separated list, sort, uniq, back to
    # space-separated list:
    newdeps=$(echo ${deplist} | tr " " "\n" | sort | uniq | tr "\n" " ")
done

kill_progress
echo -e "\n\n"

if [ "${newdeps}x" == "x" ]
then
    # We have no dependencies:
    size=0
    echo "${package} has no dependencies."
    size=$(opkg info ${package} | grep "^Size:" | cut -d " " -f 2)
    [[ "$size" = "0" ]] && echo "${package} compressed size: $((${size}/1024)) kb"
else
    someAlreadyInstalled=1 # false
    # We have at least one dependency:
    echo "The dependencies for ${package} are:"
    echo -n "    "
    for dep in ${newdeps} ${package}
    do
        if [ $(opkg list-installed | grep -q "^${dep} " ; echo $? ) -eq 0 ]
        then
            # package is already installed:
            echo -n "${dep}* "
            someAlreadyInstalled=0 # true
        else
            echo -n "${dep} "
        fi
    done
    echo
    if [ ${someAlreadyInstalled} -eq 0 ]
    then
        echo "    * already installed"
    fi

    # Get the compressed sizes for all packages and sum them up:
    byteSumAll=0
    byteSumNeeded=0
    for dep in ${newdeps} ${package}
    do
        size=$(opkg info ${dep} | grep "^Size:" | cut -d " " -f 2)
        # Check if Size is defined ("libc" doesn't list a size! 2015-01-04):
        if [ "${size}x" == "x" ]
        then
            echo "'${dep}' reports no size, ignoring."
        else
            byteSumAll=$((${byteSumAll} + ${size}))
            if [ $(opkg list-installed | grep -q "^${dep} " ; echo $? ) -eq 1 ]
            then
                # package is not installed:
                byteSumNeeded=$((${byteSumNeeded} + ${size}))
            fi
        fi
    done
    echo "${package} compressed size with deps: $((${byteSumAll}/1024)) kb"
    if [ ${someAlreadyInstalled} -eq 0 ]
    then
        echo "-> ignoring already installed packages: $((${byteSumNeeded}/1024)) kb"
    fi
fi


