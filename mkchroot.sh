#!/bin/sh
#
# build-rssh-chroot.sh - build complete rssh chroot cage
#

progname=`basename $0`

Usage() {
    echo "$progname [ CHROOTDIR ]"
    exit 1
}

CHROOTDIR=

if [ $# -gt 1 ]; then
    Usage
elif [ -n "$1" ]; then
    CHROOTDIR=$1       
else
    CHROOTDIR=/usr/local/chroot/
fi

# Sanitize CHROOTDIR to prevent confusion
CHROOTDIR="`readlink --canonicalize "$CHROOTDIR"`"
case $CHROOTDIR in
    '')
	echo "Error: blank CHROOTDIR" >&2
	exit 1
	;;
    /|*:*|*' '*)
	echo "Error: unallowed CHROOTDIR \"$CHROOTDIR\"" >&2
	exit 1
	;;
    *:*)
esac

if [ ! -d $CHROOTDIR ]; then
    echo "Error: non-existent \"$CHROOTDIR\"" >&2
    exit 1
fi

echo "progname: building chrootdir: $CHROOTDIR"

#findlibs() {
#    for bin in $@; do
#	echo Checking libraries for $bin >&2
#	if [ ! -x $1 -o ! -f $1 ]; then
#	    echo Skipping non-executable $1 >&2
#	else
#	    # Alternative listings for actual libraries
#	    ldd $1 | awk '{print $1}' | grep ^/ | \
#	    ldd $1 | awk '{print $3}' | grep ^/
#	fi
#    done
#}

rsynctarget() {
    target=$1
    if [ $# -ne 1 ]; then
	echo "Error: Bad argument to rsynctarget, exiting" >&2
	exit 1
    fi
    
    if [ ! -e "$target" ]; then
	echo "Warning: rsynctarget skipping nonexistent $target" >&2
	return 1
    fi
	
    echo "    rsynctarget: rsyncing $target"
    if [ -L "$target" ]; then
	echo "Replicating symlink: $target"
	rsync -a -H -R "$target" $CHROOTDIR
	link="`readlink "$target"`"
	case "$link" in
	    /*)
		rsynctarget $link
		;;
	    *)
		link="`dirname "$target"`/$link"
		export link
		echo  "    link with target dirname: $link"
		rsynctarget "$link"
		;;
	esac
    elif [ -d "$target" ]; then
	# Use readlink to clean out symlinks
	target="`readlink --canonicalize $target`"
	case "$target" in
	    */)
		# Replicate contents of directory
		echo "Replicating contents: $target"
		rsync -a -H -R "$target" $CHROOTDIR
		return $?
		;;
	    *)
		# Replicate directory only
		echo "Replicating directory: $target"
		rsync -a -H -R --exclude=$target/* "$target" $CHROOTDIR
		return $?
		;;
	esac
    else
	# Use readlink to clean out symlinks
	target="`readlink --canonicalize $target`"
	#echo "Replicating file: $target"
	rsync -a -H -R "$target" "$CHROOTDIR" || return $?
	return $?
    fi
}

echo "$progname: Replicating bare directories"
SOURCES=''
SOURCES="$SOURCES /dev"
SOURCES="$SOURCES /etc"
SOURCES="$SOURCES /usr"
SOURCES="$SOURCES /usr/lib"
SOURCES="$SOURCES /usr/lib64"
SOURCES="$SOURCES /usr/bin"
#SOURCES="$SOURCES /usr/sbin"
#SOURCES="$SOURCES /sbin"

# These are being replaced with symlinks in Fedora and RHEL 7
SOURCES="$SOURCES /bin"
SOURCES="$SOURCES /lib"
SOURCES="$SOURCES /lib64"

for source in $SOURCES; do
    rsynctarget "$source"
done

echo "$progname: Replicating files and populated directories"
SOURCES=''
SOURCES="$SOURCES /dev/null"
SOURCES="$SOURCES /dev/log"
SOURCES="$SOURCES /dev/urandom"
SOURCES="$SOURCES /etc/ld.so.cache"
SOURCES="$SOURCES /etc/ld.so.cache.d/"
SOURCES="$SOURCES /etc/ld.so.conf"
SOURCES="$SOURCES /etc/nsswitch.conf"
SOURCES="$SOURCES /etc/hosts"
SOURCES="$SOURCES /etc/resolv.conf"

for source in $SOURCES; do
    rsynctarget "$source"
done

echo "$progname: Replicating files and populated directories"
# Works around /bin symlinks in Fedora and RHEL 7
SOURCES=''
SOURCES="$SOURCES /bin/bash"
SOURCES="$SOURCES /bin/sh"
SOURCES="$SOURCES /usr/bin/rssh"
SOURCES="$SOURCES /usr/bin/rsync"
SOURCES="$SOURCES /usr/bin/scp"
SOURCES="$SOURCES /usr/bin/sftp"
SOURCES="$SOURCES /usr/bin/ssh"
SOURCES="$SOURCES /usr/libexec/openssh/sftp-server"
SOURCES="$SOURCES /usr/libexec/rssh_chroot_helper"
SOURCES="$SOURCES /usr/openssh/sftp-server"
SOURCES="$SOURCES /usr/sbin/pwconv"
SOURCES="$SOURCES /usr/sbin/pwunconv"
SOURCES="$SOURCES /usr/sbin/grpconv"
SOURCES="$SOURCES /usr/sbin/grpunconv"

SOURCES="$SOURCES /etc/nsswitch.conf"

SOURCES="$SOURCES /bin/cat"
SOURCES="$SOURCES /bin/su"
SOURCES="$SOURCES /bin/pwd"
SOURCES="$SOURCES /bin/ls"
SOURCES="$SOURCES /usr/bin/ldd"
SOURCES="$SOURCES /usr/bin/id"
SOURCES="$SOURCES /usr/bin/getent"
SOURCES="$SOURCES /usr/bin/groups"
SOURCES="$SOURCES /usr/bin/whoami"

for source in $SOURCES; do
    rsynctarget $source
    if [ ! -x "$source" ]; then
	continue
    elif [ -d "$source" ]; then
	continue
    elif [ -L "$source" ]; then
	continue
    fi

    echo "    Calculating libraries for $source"
    (ldd "$source" | awk '{print $1}'; ldd "$source" | awk '{print $3}') | \
	sort -u | \
	grep ^/ | \
	while read lib; do
	    echo "Replicating $source library: $lib"
	    rsynctarget $lib
    done
done

# Get NSS libraries
find /llb/ /lib64/ /usr/lib/ /ur/lib64/ ! -type d -name libnss\* | \
    while read lib; do
    rsynctarget $lib
done




# Ensure correct umask for file generation
umask 022
# Clear credential files before starting
rm -f $CHROOTDIR/etc/passwd
rm -f $CHROOTDIR/etc/group
touch $CHROOTDIR/etc/passwd
touch $CHROOTDIR/etc/group
# Only creat accounts for rssh enabled users
grep ":$CHROOTDIR" /etc/passwd | \
    sed "s|:$CHROOTDIR|:/|g"  | \
    sed 's|://|:/|g' > $CHROOTDIR/etc/passwd

# Optional: activate additional chroot targets, as needed
grep ^root: /etc/passwd >> $CHROOTDIR//etc/passwd
grep ^rsshusers: /etc/passwd >> $CHROOTDIR//etc/passwd

sort -u -o $CHROOTDIR/etc/passwd $CHROOTDIR/etc/passwd
echo Working $CHROOTDIR/etc/passwd:
cat $CHROOTDIR/etc/passwd

# Deduce all relevant groups for users
CHROOTUSERS="`cut -f1 -d: $CHROOTDIR/etc/passwd`"
if [ -z "$CHROOTUSERS" ]; then
    echo "Warning: No CHROOTUSERS found, making blank $CHROOTDIR/etc/group"
    touch $CHROOTDIR/etc/group
fi

for user in $CHROOTUSERS; do
    groups="`id -n --groups $user`"
    for group in $groups; do
	echo checking for group name: $group
	grep ^"$group:" /etc/group >> $CHROOTDIR/etc/group
    done
done
sort -u -o $CHROOTDIR/etc/group $CHROOTDIR/etc/group
echo
echo Reporting group file: $CHROOTDIR/etc/group
cat $CHROOTDIR/etc/group
