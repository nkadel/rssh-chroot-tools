#!/bin/sh
#
# mkchroot-passwd.sh - build rssh compatible /etc/passwd
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

# Ensure correct umask for file generation
umask 022
# Clear credential files before starting
rm -f $CHROOTDIR/etc/passwd
rm -f $CHROOTDIR/etc/group

mkchrootuser() {
    user=$1
    if [ -z "$user" ]; then
	echo "Error: user cannot be blank, returning" >&2
	return 1
    fi
    echo "mkchrootuser: creating $user"
    groups="`id -n --groups $user`"
    if [ -z "$groups" ]; then
	echo "Error: cannot deduce groups for $user, returning" >&2
	return 1
    fi

    homeowner="`getent passwd $user | awk -F: '{print $3}'`"
    homegroup="`getent passwd $user | awk -F: '{print $4}'`"

    # extract normalized homedir
    homedir="`getent passwd $user | awk -F: '{print $6}'`"
    if [ -z "$homedir" ]; then
	echo "Error, getent cannot resolve homedir of $user, returning" >&2
	return 1
    fi

    case $homedir in
	"${CHROOTDIR}")
	    echo "  Replacing $homedir with /"
	    homedir="/"
	    ;;
	"${CHROOTDIR}"/*)
	    echo "  Stripping CHROOTDIR from $homedir"
	    homedir="`echo "$homedir" | sed "s|^$CHROOTDIR/|/|g"`"
	    ;;
	*)
	    ;;
    esac
    # Encure presence of at least empty homedir inside chroot cage
    if [ ! -e "$CHROOTDIR/$homedir" ]; then
	echo "Creating empty $homedir in $CHOROOTDIR"
	install -d -o $homeowner -g $homegroup "$CHROOTDIR"/"$homedir"
    fi

    cat <<EOF
Putting $user in $CHROOTDIR/etc/passwd
    homedir: $homedir
EOF

    getent passwd $user | \
	sed "s|:$CHROOTDIR:|:/:|g" | \
	sed "s|:$CHROOTDIR/|:/|g" >> $CHROOTDIR/etc/passwd
    sort -u -n -k3 -t: -o $CHROOTDIR/etc/passwd $CHROOTDIR/etc/passwd

    # not perfect, leaves extraneous group members!!
    for group in $groups; do
	grep "^$group:" /etc/group >> $CHROOTDIR/etc/group
    done
    sort -u -n -k3 -t: -o $CHROOTDIR/etc/group $CHROOTDIR/etc/group
}

# Only creat accounts for rssh enabled users
getent passwd | \
    grep ":$CHROOTDIR" | \
    cut -f1 -d: | \
    while read user; do
    mkchrootuser "$user"
done

# Add root user for debugging
mkchrootuser root

cat  $CHROOTDIR/etc/passwd
