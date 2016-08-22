#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="autoeditor-Qthttpd"
QPKG_ROOT=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
APACHE_ROOT=/share/`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`

SAVED_DIR="$QPKG_ROOT/originfiles"
if [ ! -d "$SAVED_DIR" ]; then
	echo "$SAVED_DIR not exists."
	exit 1
fi

QTHTTPD_INIT_FILENAME="Qthttpd.sh"
QTHTTPD_INIT="/etc/init.d/$QTHTTPD_INIT_FILENAME"
if [ ! -e "$QTHTTPD_INIT" ]; then
	echo "$QTHTTPD_INIT not exists."
	exit 1
fi

SAVED_QTHTTPD_INIT="$SAVED_DIR/$QTHTTPD_INIT_FILENAME"

get_const()
{
	# $1 -- const name

	/bin/sed -rn "s/^$1=\"([^\"]*)\".*\$/\\1/p" "$QTHTTPD_INIT" 2>/dev/null | head -n 1
}

PHPFPM_PID=`get_const "PHPFPM_PID"`
if [ -z "$PHPFPM_PID" ]; then
	echo "Variable PHPFPM_PID is not defined in the file $QTHTTPD_INIT."
	exit 1
fi

APACHE_PID_FILE=`get_const "APACHE_PID_FILE"`
if [ -z "$APACHE_PID_FILE" ]; then
	echo "Variable APACHE_PID_FILE is not defined in the file $QTHTTPD_INIT."
	exit 1
fi

get_status_qthttpd_init()
{
	STATUS="unknown"

	if /bin/grep '^[[:space:]]*PHPFPM_CONF='  "$QTHTTPD_INIT" &>/dev/null; then
		PHPFPM_CONF=`get_const "PHPFPM_CONF"`

		case "$PHPFPM_CONF" in
			"/etc/default_config/php-fpm.conf")
				STATUS="default_config"
				;;
			"/etc/config/php-fpm.conf")
				STATUS="config"
				;;
			*)
				if /bin/grep '^[[:space:]]*DPHPFPM_CONF=' "$QTHTTPD_INIT" &>/dev/null && /bin/grep '^[[:space:]]*UPHPFPM_CONF=' "$QTHTTPD_INIT" &>/dev/null; then
					STATUS="auto"
				fi
				;;
		esac
	fi

	echo "$STATUS"
}

QTHTTPD_INIT_STATUS=`get_status_qthttpd_init`

if [ "$QTHTTPD_INIT_STATUS" = "unknown" ]; then
	echo "$QTHTTPD_INIT unknown file format."
	exit 1
fi

is_run()
{
	# $1 -- process name
	# $2 -- pid file

	/bin/pidof "$1" | /bin/egrep "^(|.*[[:space:]])`/bin/cat "$2"`(|[[:space:]].*)\$" &>/dev/null
}

edit_qthttpd_init()
{
	# save the original Qthttpd.sh
	echo "Save the original $QTHTTPD_INIT."
	/bin/rm -f "$SAVED_QTHTTPD_INIT"
	/bin/cp -fa "$QTHTTPD_INIT" "$SAVED_QTHTTPD_INIT"

	# edit Qthttpd.sh
	echo "Edit the original $QTHTTPD_INIT."
	/bin/sed -ri 's@^PHPFPM_CONF="/etc/default_config/php-fpm.conf"[[:space:]]*$@DPHPFPM_CONF="/etc/default_config/php-fpm.conf"\nUPHPFPM_CONF="/etc/config/php-fpm.conf"\nif [ -f "$UPHPFPM_CONF" ]; then\n	PHPFPM_CONF="$UPHPFPM_CONF"\nelse\n	PHPFPM_CONF="$DPHPFPM_CONF"\nfi@' "$QTHTTPD_INIT"
}

restore_qthttpd_init()
{
	# restore Qthttpd.sh
	echo "Restore the original $QTHTTPD_INIT."
	rm -f "$QTHTTPD_INIT"
	mv "$SAVED_QTHTTPD_INIT" "$QTHTTPD_INIT"
}

update_qthttpd_init()
{
	# $1 -- comand for run

	# stop apache and php-fpm
	if is_run "apache" "$APACHE_PID_FILE" || is_run "php-fpm" "$PHPFPM_PID"; then
		START_QTHTTPD="yes"
		"$QTHTTPD_INIT" stop
	else
		START_QTHTTPD="no"
	fi

	# run command
	"$1"

	# start apache and php-fpm
	if [ "$START_QTHTTPD" = "yes" ]; then
		"$QTHTTPD_INIT" start
	fi
}

ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
case "$1" in
	edit)
		if [ "$QTHTTPD_INIT_STATUS" = "default_config" ]; then
			update_qthttpd_init "edit_qthttpd_init"
		fi
		;;
	restore)
		if [ -f "$SAVED_QTHTTPD_INIT" ]; then
			if [ "$QTHTTPD_INIT_STATUS" = "auto" ] || [ "$QTHTTPD_INIT_STATUS" = "config" ]; then
				update_qthttpd_init "restore_qthttpd_init"
			fi
		fi
		;;
	start)
		if [ "$ENABLED" != "TRUE" ]; then
				echo "$QPKG_NAME is disabled."
				$0 restore
				exit 1
		fi
		: ADD START ACTIONS HERE
		$0 edit
		;;

	stop)
		: ADD STOP ACTIONS HERE
		if [ "$ENABLED" != "TRUE" ]; then
				$0 restore
		fi
		;;

	restart)
		$0 stop
		$0 start
		;;

	*)
		echo "Usage: $0 {start|stop|restart|edit|restore}"
		exit 1
esac

exit 0
