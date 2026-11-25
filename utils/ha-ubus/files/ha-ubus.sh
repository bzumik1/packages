#!/bin/sh

. /lib/functions.sh
. /lib/functions/network.sh

USERNAME="homeassistant"
SECTION="ha_ubus"
ACL_GROUP="ha-ubus"
CRED_DIR="/etc/ha-ubus"
CRED_FILE="$CRED_DIR/password"
LEASE_FILE="/tmp/dhcp.leases"
PASSWORD_LENGTH=24

CONFLICT=""

login_exists() {
	[ "$(uci -q get "rpcd.$SECTION")" = "login" ]
}

match_conflict() {
	local name

	[ "$1" = "$SECTION" ] && return 0
	config_get name "$1" username
	[ "$name" = "$USERNAME" ] && CONFLICT="$1"
}

check_conflict() {
	CONFLICT=""
	config_load rpcd
	config_foreach match_conflict login
	[ -z "$CONFLICT" ] && return 0

	echo "Another rpcd login ($CONFLICT) already uses the username '$USERNAME'." >&2
	echo "Remove it and run 'ha-ubus reset'." >&2
	return 1
}

set_password() {
	local password hash

	password="$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$PASSWORD_LENGTH")"
	if [ "${#password}" -ne "$PASSWORD_LENGTH" ]; then
		echo "Failed to generate a password." >&2
		return 1
	fi

	hash="$(uhttpd -m "$password")"
	case "$hash" in
	"\$1\$"*) ;;
	*)
		echo "Failed to hash the password." >&2
		return 1
		;;
	esac

	mkdir -p "$CRED_DIR" || return 1
	chmod 700 "$CRED_DIR" || return 1
	( umask 077 && printf '%s\n' "$password" > "$CRED_FILE.new" ) || return 1

	if ! uci set "rpcd.$SECTION.password=$hash" || ! uci commit rpcd; then
		uci revert rpcd
		rm -f "$CRED_FILE.new"
		echo "Failed to store the password in /etc/config/rpcd." >&2
		return 1
	fi

	mv "$CRED_FILE.new" "$CRED_FILE"
}

revoke_sessions() {
	local sid user

	for sid in $(ubus call session list 2>/dev/null | sed -n 's/.*"ubus_rpc_session": "\([0-9a-f]*\)".*/\1/p'); do
		user="$(ubus call session get "{\"ubus_rpc_session\":\"$sid\",\"keys\":[\"username\"]}" 2>/dev/null | jsonfilter -e '@.values.username' 2>/dev/null)"
		[ "$user" = "$USERNAME" ] || continue
		ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}"
	done

	return 0
}

lan_address() {
	local address

	network_get_ipaddr address lan
	[ -n "$address" ] || address="$(uci -q get network.lan.ipaddr)"
	address="${address%%/*}"
	echo "${address%% *}"
}

dhcp_software() {
	local maindhcp

	config_load dhcp
	config_get_bool maindhcp odhcpd maindhcp 0
	if [ "$maindhcp" = "1" ]; then
		echo "odhcpd"
	elif [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq enabled; then
		echo "dnsmasq"
	else
		echo "none"
	fi
}

check_lease_file() {
	[ "$(uci -q get 'dhcp.@dnsmasq[0].leasefile')" = "$LEASE_FILE" ] && return 0

	echo "Warning: dhcp.@dnsmasq[0].leasefile is not '$LEASE_FILE'." >&2
	echo "Home Assistant reads the lease file from that option, and this login can only read '$LEASE_FILE'." >&2
}

cmd_setup() {
	login_exists && return 0
	check_conflict || return 1

	uci set "rpcd.$SECTION=login"
	uci set "rpcd.$SECTION.username=$USERNAME"
	uci add_list "rpcd.$SECTION.read=$ACL_GROUP"
	uci add_list "rpcd.$SECTION.read=unauthenticated"
	set_password
}

cmd_reset() {
	if ! login_exists; then
		cmd_setup
		return
	fi

	set_password || return 1
	revoke_sessions
}

cmd_show() {
	local dhcp

	if ! login_exists || [ ! -s "$CRED_FILE" ]; then
		echo "No stored password for '$USERNAME'. Run 'ha-ubus reset' to create one." >&2
		return 1
	fi

	dhcp="$(dhcp_software)"
	echo "Home Assistant OpenWrt (ubus) integration:"
	echo "  Host:          $(lan_address)"
	echo "  Username:      $USERNAME"
	echo "  Password:      $(cat "$CRED_FILE")"
	echo "  DHCP software: $dhcp"
	[ "$dhcp" = "dnsmasq" ] && check_lease_file
	return 0
}

cmd_remove() {
	rm -rf "$CRED_DIR"
	login_exists || return 0

	uci delete "rpcd.$SECTION"
	uci commit rpcd
	revoke_sessions
}

usage() {
	cat <<EOF
Usage: ha-ubus <command>

Commands:
  setup   Create the read-only '$USERNAME' login if it does not exist
  show    Print the values to enter in Home Assistant
  reset   Generate a new password and log out existing sessions
  remove  Delete the login, the stored password and existing sessions
EOF
}

case "$1" in
	setup) cmd_setup ;;
	show) cmd_show ;;
	reset) cmd_reset && cmd_show ;;
	remove) cmd_remove ;;
	*) usage; exit 1 ;;
esac
