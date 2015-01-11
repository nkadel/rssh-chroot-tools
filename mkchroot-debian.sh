#!/bin/bash

#####################################################################
#####################################################################
##
## mkchroot.sh - set up a chroot jail.
##
## This script is written to work for Red Hat 8/9 systems and adapted to work
## on Debian systems, but may work on other systems.  Or, it may not...  In
## fact, it may not work at all.  Use at your own risk.  :)
##

fail() {

	echo "`basename $0`: fatal error" >&2
	echo "$1" >&2
	exit $2
}

#####################################################################
#
# Initialize - handle command-line args, and set up variables and such.
# 
# $1 is the directory to make the root of the chroot jail (required)
# $2, if given, is the user who should own the jail (optional)
# $3, if given,  is the permissions on the directory (optional) 
#

if [ -z "$1" ]; then
	echo "`basename $0`: error parsing command line" >&2
	echo "  You must specify a directory to use as the chroot jail." >&2
	exit 1
fi

jail_dir="$1"

if [ -n "$2" ]; then
	owner="$2"
fi

if [ -n "$3" ]; then
	perms="$3"
fi


#####################################################################
#
# build the jail
#

# now make the directory

if [ ! -d "$jail_dir" ]; then
	echo "Creating root jail directory."
	mkdir -p "$jail_dir"
	
	if [ $? -ne 0 ]; then
		echo "  `basename $0`: error creating jail directory." >&2
		echo "Check permissions on parent directory." >&2
		exit 2
	fi
fi

if [ -n "$owner" -a `whoami` = "root" ]; then
	echo "Setting owner of jail."
	chown "$owner" "$jail_dir"
	if [ $? -ne 0 ]; then
		echo "  `basename $0`: error changing owner of jail directory." >&2
		exit 3
	 fi
else
	echo -e "NOT changing owner of root jail. \c"
	if [ `whoami` != "root" ]; then
		echo "You are not root."
	else
		echo
	fi
fi

if [ -n "$owner" -a `whoami` = "root" ]; then
	echo "Setting permissions of jail."
	chmod "$perms" "$jail_dir"
	if [ $? -ne 0 ]; then
		echo "  `basename $0`: error changing perms of jail directory." >&2
		exit 3
	 fi
else
	echo -e "NOT changing perms of root jail. \c"
	if [ `whoami` != "root" ]; then
		echo "You are not root."
	else
		echo
	fi
fi

# copy SSH files

scp_path="/usr/bin/scp"
sftp_server_path="/usr/lib/openssh/sftp-server"
rssh_path="/usr/bin/rssh"
chroot_helper_path="/usr/lib/rssh/rssh_chroot_helper"

for jail_path in `dirname "$jail_dir$scp_path"` `dirname "$jail_dir$sftp_server_path"` `dirname "$jail_dir$chroot_helper_path"`; do

	echo "setting up $jail_path"

	if [ ! -d "$jail_path" ]; then
		mkdir -p "$jail_path" || \
			fail "Error creating $jail_path. Exiting." 4
	fi

done

cp "$scp_path" "$jail_dir$scp_path" || \
	fail "Error copying $scp_path. Exiting." 5
cp "$sftp_server_path" "$jail_dir$sftp_server_path" || \
	fail "Error copying $sftp_server_path. Exiting." 5
cp "$rssh_path" "$jail_dir$rssh_path" || \
	fail "Error copying $rssh_path. Exiting." 5
cp "$chroot_helper_path" "$jail_dir$chroot_helper_path" || \
	fail "Error copying $chroot_helper_path. Exiting." 5


#####################################################################
#
# identify and copy libraries needed in the jail
#
# Sample ldd output:
#
#   linux-gate.so.1 =>  (0xffffe000)
#   libresolv.so.2 => /lib/i686/cmov/libresolv.so.2 (0xb7ef2000)
#   libcrypto.so.0.9.8 => /usr/lib/i686/cmov/libcrypto.so.0.9.8 (0xb7da8000)
#   libutil.so.1 => /lib/i686/cmov/libutil.so.1 (0xb7da3000)
#   libz.so.1 => /usr/lib/libz.so.1 (0xb7d8e000)
#   libnsl.so.1 => /lib/i686/cmov/libnsl.so.1 (0xb7d76000)
#   libcrypt.so.1 => /lib/i686/cmov/libcrypt.so.1 (0xb7d44000)
#   libgssapi_krb5.so.2 => /usr/lib/libgssapi_krb5.so.2 (0xb7d1b000)
#   libkrb5.so.3 => /usr/lib/libkrb5.so.3 (0xb7c8d000)
#   libk5crypto.so.3 => /usr/lib/libk5crypto.so.3 (0xb7c69000)
#   libcom_err.so.2 => /lib/libcom_err.so.2 (0xb7c66000)
#   libc.so.6 => /lib/i686/cmov/libc.so.6 (0xb7b19000)
#   libdl.so.2 => /lib/i686/cmov/libdl.so.2 (0xb7b15000)
#   libkrb5support.so.0 => /usr/lib/libkrb5support.so.0 (0xb7b0d000)
#   libkeyutils.so.1 => /lib/libkeyutils.so.1 (0xb7b09000)
#   /lib/ld-linux.so.2 (0xb7f13000)
#
# either the first or the third column may contain a path
#

for prog in $scp_path $sftp_server_path $rssh_path $chroot_helper_path \
            /lib/libnss_compat* /lib/libnss_files* /lib/*/libnss_comat* \
            /lib/*/libnss_files*; do
	if [ ! -f "$prog" ] ; then
		continue
	fi
	echo "Copying libraries for $prog."
	libs=`ldd $prog | awk '$1 ~ /^\// {print $1} $3 ~ /^\// {print $3}'`
	for lib in $libs; do
		mkdir -p "$jail_dir$(dirname $lib)" || \
			fail "Error creating $(dirname $lib). Exiting" 6
		echo -e "\t$lib"
		cp "$lib" "$jail_dir$lib" || \
			fail "Error copying $lib. Exiting" 6
	done
done

# On Debian with multiarch, the libnss files are in /lib/<triplet>, where
# <triplet> is the relevant architecture triplet.  Just copy everything
# that's installed, since we're not sure which ones we'll need.
echo "copying name service resolution libraries..."
if [ -n "$(find /lib -maxdepth 1 -name 'libnss*_' -print -quit)" ] ; then
    tar -cf - /lib/libnss_compat* /lib/libnss*_files* \
        | tar -C "$jail_dir" -xvf - | sed 's/^/\t/'
else
    tar -cf - /lib/*/libnss_compat* /lib/*/libnss*_files* \
        | tar -C "$jail_dir" -xvf - | sed 's/^/\t/'
fi

#####################################################################
#
# copy config files for the dynamic linker, nsswitch.conf, and the passwd file
#

echo "Setting up /etc in the chroot jail"
mkdir -p "$jail_dir/etc" || fail "Error creating /etc. Exiting" 7
cp /etc/nsswitch.conf "$jail_dir/etc/" || \
	fail "Error copying /etc/nsswitch.conf. Exiting" 7
cp /etc/passwd "$jail_dir/etc/" || \
	fail "Error copying /etc/passwd. Exiting" 7
cp -r /etc/ld.* "$jail_dir/etc/" || \
	fail "Error copying /etc/ld.*. Exiting" 7
echo -e "\nWARNING: Copying /etc/passwd into the chroot jail.  You may wish"
echo -e "to edit out unnecessary users and remove any sensitive information"
echo -e "from it."

#####################################################################
#
# set up /dev
#

mkdir -p "$jail_dir/dev"
if [ `whoami` = "root" ]; then
	cp -a /dev/log "$jail_dir/dev" || \
		fail "Error creating /dev/log. Exiting" 8
	cp -a /dev/null "$jail_dir/dev" || \
		fail "Error creating /dev/null. Exiting" 8
	cp -a /dev/zero "$jail_dir/dev" || \
		fail "Error creating /dev/zero. Exiting" 8
else
	echo -e "NOT creating /dev/null and /dev/log in the chroot jail. \c"
	echo -e "You are not root.\n"
fi

echo -e "Chroot jail configuration completed.\n"

echo -e "NOTE: if you are not using the passwd file for authentication,"
echo -e "you may need to copy some of the /lib/libnss_* files into the jail.\n"

echo -e "NOTE: if you are using any programs other than scp and sftp, you will"
echo -e "need to copy the server binaries and any libraries they depend on"
echo -e "into the chroot manually.  Use ldd on the binary to find the needed"
echo -e "libraries.\n"

echo -e "NOTE: you must MANUALLY edit your syslog rc script to start syslogd"
echo -e "with appropriate options to log to $jail_dir/dev/log.  In most cases,"
echo -e "you will need to start syslog as:\n"
echo -e "   /sbin/syslogd -a $jail_dir/dev/log\n\n"

echo -e "NOTE: we make no guarantee that ANY of this will work for you... \c"
echo -e "if it\ndoesn't, you're on your own.  Sorry!\n"
