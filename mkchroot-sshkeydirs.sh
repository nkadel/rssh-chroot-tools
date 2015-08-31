#!/bin/sh
#
# mkchroot-keydirs.sh - build rssh compatible /etc/passwd
#

progname=`basename $0`

Usage() {
    echo "$progname [ CHROOTDIR ]"
    exit 1
}

if [ $# -gt 1 ]; then
    Usage
elif [ -n "$1" ]; then
    CHROOTDIR=$1       
else
    CHROOTDIR=/chroot/
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

function mksshdir() {
    sshdir="$1"
    uid="$2"
    gid="$3"
    if [ -e "$sshdir" ]; then
	if [ ! -d "$sshdir" ]; then
	    echo "Error: $sshdir exists, but is not a directory, exiting" >&2
	    exit 1
	fi
	echo "    $sshdir exists already"
	#return 0
    else
	parentdir="`dirname $sshdir`"
	if [ ! -d "$parentdir" ]; then
	    mksshdir "$parentdir" $uid $gid
	else
	    echo "    Creating directory: $sshdir"
	    install -d -o $uid -g $gid -m 0750 "$sshdir"
	fi
    fi
}

getent passwd | \
    grep ":$CHROOTDIR" | \
    while IFS=: read username passwd uid gid comment homedir shell debris; do
    if [ -n "$debris" ]; then
	echo "Error: user $username has invalid getent content, exiting" >&2
	exit 1
    fi

    #echo CHROOTDIR: $CHROOTDIR
    #echo homedir: $homedir
    case $homedir in
	"$CHROOTDIR" )
	    ;;
	${CHROOTDIR}/* )
	    ;;
	*)
	    continue
	    ;;
    esac

    # Always set "root" as owner
    mksshdir "$homedir" root "$gid"

done
