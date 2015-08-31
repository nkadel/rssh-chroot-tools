*** rssh-chroot-tools ***

[ Available at https://github.com/nkadel/rssh-chroot-tools/. ]

These tools are based on the 'mkchroot.sh' script from
rssh-2.3.4. They're noticeably more powerful, safer, and easier to
expand. They're also a "one-stop" operation on RHEL 6 based operating
systems, much more recent and compatibile than the many Debian
specific guidelines on the net.

This approach is also much more portable, and safer, than applying
local chroot patches to OpenSSH: that approach is strongly discouraged
by the OpenSSH maintainers.

* The 'mkchroot.sh' has a default location of "/chroot"
** mkcroot.sh now does not auto-create the base chroot directory: that's
   the task of the local sysadmin to pick and set the appropriate
   working directory.
** mkchroot.sh now uses "rsync -a --hard-links --relative" exclusively for
   replicating content. This is far more efficient, and much safer,
   than using "cp", since it moves aside files and replaces them
   rather than overwriting them.
** mhchroot.sh now far more meaningful error messages than the old
   rssh embedded scripts, , and exits if critcal operations fail.
** mhchroot.sh now *skips* but reports non-existent source files.
** mkchroot.sh now handles symlinks correctly, including the libnss
   symlinks that would ordinarily reach outside of the chroot directory.
** mkchroot.sh now has numerous commented out but optionally enabled
   debugging tools, including /bin/sh, /usr/bin/id, and
   /usr/bin/pwgetconv.
** mkchroot.sh now deduces and replicates critical libnss libraries
   from whichever /lib, /lib64, /usr/lib/, etc. directory contains them.
** mkchroot.sh now pre-creates directories like "/lib" and "/lib64" to
   deal with CentOS and Fedora symlink usage.

* Management of account creation, especially the "etc/passwd" and
 "etc/group", has been moved to a swparate script "mkchroot-passwd.sh"
** mkchroot-passwd.sh uses 'getent' to deduce relevant accounts.
** mkchroot-passwd.sh creates the users's home directory in the
   chroot cage if it does not already exist.
** mkchroot-passwd.sh deduces the relevant /etc/group entries so that
   the "rsshuser" suid programs work correctly.

* Working ownership and privileges for chroot cage SSH keys can now be
  set with the mkchroot-sshkeydirs.sh script.
** New directories to hold SSH public keys are created with root
   ownership and read-only group for the designated account
   owner. This prevents an the user from resetting their own
   credentials.
** If none is present, the script creates an empty, root owned
   authorized_keys file.

               Nico Kadel-Garcia <nkadel@gmsil.com>
