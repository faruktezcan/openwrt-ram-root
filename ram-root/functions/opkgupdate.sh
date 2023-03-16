opkg_update () {
  local time=0
  local interactive=${1}
  local dir=$(grep lists_dir /etc/opkg.conf | awk '{print $3}')
  local f1 f2 f3

  [[ $# -ge 1 && "$interactive" != "-i" ]] && interactive="-i"
  [[ -d $dir ]] && [[ -n "$(ls -1A $dir)" ]] && let time=$(date +%s)-$(date -r $dir +%s)
  [[ $time -ge 600 ]] && time=0

  if [[ $time -eq 0 ]]; then
    if ( ! ping -c 1 downloads.openwrt.org &>/dev/null ); then return 1; fi

    echo -e "\a\e[1mUpdating repositories\e[0m\n"
    local opkgdir=/tmp/opkg-lists
    mkdir $opkgdir &>/dev/null
    cd $opkgdir

    while read f1 f2 f3; do
      echo -n "$f2..."
      if ( ln -f $opkgdir/$f2 $opkgdir/Packages.gz &>/dev/null ); then
        wget -q $f3/Packages.gz 2>&1
      else
        wget -q -O $opkgdir/$f2 $f3/Packages.gz 2>&1
      fi
      if ( ln -f $opkgdir/$f2.sig $opkgdir/Packages.sig &>/dev/null ); then
        wget -q $f3/Packages.sig 2>&1
      else
        wget -q -O $opkgdir/$f2.sig $f3/Packages.sig 2>&1
      fi
      echo -e "\e[1mdone\e[0m"
    done < /etc/opkg/distfeeds.conf

    rm $opkgdir/Packages.* &>/dev/null
    echo
  fi

  return 0
}
