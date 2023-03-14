#!/bin/sh
PRECISION=6

trunk_time () {
  PKGTIME=$(opkg info "$1" | grep '^Installed-Time: ' | cut -f2 -d ' ')
  PKGTIME=${PKGTIME:0:$2}
  return
}

trunk_time busybox $PRECISION && BUILD_TIME=$PKGTIME

for i in $(opkg list-installed | cut -d' ' -f1)
do
  trunk_time $i $PRECISION
  if [ "$PKGTIME" != "$BUILD_TIME" ]; then
    echo $i
  fi
done
