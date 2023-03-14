Introduction:
+++++++++++++

- If you have a router without a USB port, it is very likely that with more intense usage of your router, you will need more disk space
and/or
- You may want to test new software or config options or upgrade package(s) without changing your original setup to make sure everyting works properly.

-These can be achieved by creating a ram drive (tmpfs) in your router's memory and using it as your new storage space. With this option, you can install 
and test new packages beyond your flash drive’s capacity to see how they work. As soon as you reboot your router you will go back to your former state.

-The ability of saving your ram drive in a local/remote share and restoring it back to your router is also given to you as an option.

-Installing optional 'zram-swap' is highly adviced as this package provides you approx. %50 more storage space.

-For further explanation/investigation please check the self-explanatory config file.


Installation:
+++++++++++++

-Download the provided ‘ram-root.tar.gz’ file and extract it with this command: 'tar -C / -vzxf ram-root.tar.gz'

-After the extraction you should have a new directory named ‘/ram-root’.

-You should additionally make some changes in the ‘config’ file according to your needs before running the script for the 1st time.

-Install optional 'zram-swap' package considering your available flash drive space.

-The script will check if all the required packages are installed and will do it automatically if not.


How to use:
+++++++++++

- 'sh /ram-root/ram-root.sh init'
This has to be run for the first time from your console to start the ram-root installation on your router and the server.
The script will copy itself into '/etc/init.d' for further operations.

- '/etc/init.d/ram-root start'
This starts ram-root opereation from your backup if you already have one.

- '/etc/init.d/ram-root stop'
This is the command to stop the process and reboot the router to its original state.
If backup option is selected, a backup will be done before rebooting.

- '/etc/init.d/ram-root backup'
If you want to keep your new ram-root settings, it is possible to make a backup in your local/remote share.
The server could be anywhere reachable by your router.
If you select the backup option in the ‘config’ file, the script will make the backup for the first installation automatically.
You can also backup any time you want by initiating the command from your console.

- '/etc/init.d/ram-root reset'
If you need to reset your ram drive backup and make a fresh start, enter this command. The command will bypass your backup file.

- '/etc/init.d/ram-root status'
Shows ram-root status if it is running or not.

- '/etc/init.d/ram-root upgrade'
Run 'opkg upgrade' command to upgrade the system.


Notes:
++++++

You can enable the autorun option by entering '/etc/init.d/ram-root enable' to boot your router through the 'ram-root',
if you make sure that everything works quite nicely.

The previous state of the router is mounted under '/old-root'. You can simply switch to that and make changes to your base system.


Included scripts in 'tools' directory:
++++++++++++++++++++++++++++++++++++++

'opkgclean.sh'   : Cleans unsuccesful installation attempt debris due to flash storage shortage

'opkgdeps.sh'    : Lists all dependant packages for the given package

'opkgupgrade.sh' : Upgrades whole system packages interactively

'overlaypkgs.sh' : Saves user-installed packages before upgrade and restore them later.

'ssh-copy-id'    : Copies your ssh credentials to the remote device for easier ssh connections.
