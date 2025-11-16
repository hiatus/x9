# To be sourced by `~/.bashrc`

if ! hash script jq sqlite3 uuidgen 2>/dev/null; then
	echo '[x9] The following dependencies must be installed: script jq sqlite3 uuidgen'
	return
fi

tty | grep -q -E '^/dev/tty[0-9]+$' && return

if [ -z $X9_SESSION_ID ]; then
	export X9_SESSION_ID="$(uuidgen -r)"
	export X9_DATABASE="${HOME}/.local/share/x9/x9.db"
	export X9_SESSION_ROOT="${HOME}/.local/share/x9/session"
fi

if ! [ -r "$X9_DATABASE" ]; then
	if ! mkdir -p "$(dirname "$X9_DATABASE")"; then
		unset X9_SESSION_ID X9_DATABASE X9_SESSION_ROOT
		return
	fi

	if ! sqlite3 "$X9_DATABASE" 'CREATE TABLE session (session_id TEXT PRIMARY KEY, start_date TEXT, end_date TEXT); CREATE TABLE command (session_id TEXT, start_date TEXT, end_date TEXT, hostname TEXT, ipv4_cidr TEXT, username TEXT, cwd TEXT, command_line TEXT, return_code INTEGER);'; then
		unset X9_SESSION_ID X9_DATABASE X9_SESSION_ROOT
		return
	fi
fi

if ! mkdir -p "$X9_SESSION_ROOT" 2> /dev/null; then
	echo -e "Failed to start X9 session: failed to create log directory at ${wd}\n"
	unset X9_SESSION_ID X9_DATABASE X9_SESSION_ROOT
	return
fi

x9-find-commands() {
	local query="SELECT * FROM command WHERE command_line LIKE '%${1}%';"
	sqlite3 -json "$X9_DATABASE" "$query" | jq .
}

x9-find-sessions() {
	local query="SELECT * FROM session WHERE session_id LIKE '%${1}%';"
	sqlite3 -json "$X9_DATABASE" "$query" | jq .
}

x9-session() {
	local session_path="$(ls "${X9_SESSION_ROOT}/${2}"_* 2> /dev/null | head -1)"

	if ! [[ "$1" =~ ^(print|play)$ ]] || [ -z "$2" ] || ! [ -r "$session_path" ]; then
		echo 'Usage: x9-session [print|play] [session-id]'
		return 1
	fi

	if ! tmp_dir="$(mktemp -d)"; then
		echo '[!] Failed to create temporary directory'
		return 2
	fi

	cleanup() { rm -rf "$tmp_dir"; }
	trap cleanup EXIT INT

	tar -xJf "$session_path" -C "$tmp_dir"
	[ "$1" = 'print' ] && cat "${tmp_dir}/typescript" || scriptreplay "${tmp_dir}/timescript" "${tmp_dir}/typescript"

	rm -rf "$tmp_dir"
}

__x9_get_network_interface_cidr() {
	ipv4_cidr="$(ip -o -4 address show dev "$iface" 2> /dev/null | awk '{print $4}')"
	[ -n "$ipv4_cidr" ] && echo "$ipv4_cidr" && return 0 || return 1
}

__x9_get_network_interface() {
	# Prefer the interface that owns the default route
	iface=$(
		ip -4 route list default 0.0.0.0/0 2>/dev/null |
        	awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i+1); exit } }'
	)

	# If there is no default route, fall back to the first "sane" global interface that has an
	# IPv4 address
	if [ -z $iface ]; then
		for i in /sys/class/net/!(lo|docker*|veth*|virbr*|br-*|vmnet*|zt*); do
			__x9_get_network_interface_cidr "$i" || continue

			iface="$i"
			break
		done
	fi

	# If there is still no interface, go for the loopback interface
	[ -z "$iface" ] && iface="$(ip -o link show | awk '$3 ~ /LOOPBACK/ {print $2}' | tr -d ':')"

	# Return the interface
	[ -n "$iface" ] && echo "$iface" && return 0 || return 1
}

# Hook PROMPT_COMMAND
__x9_hook() {
	local ret=$?

	[ -z "$HISTFILE" ] && return
	[[ -n $X9_SESSION_ID  && -r "$X9_DATABASE" ]] || return

	# Get last command information
	lc_info=($(HISTTIMEFORMAT='%s ' history 1 | sed 's/^[ ]*[0-9]\+[ ]*//'))
	lc_date="$(date -d @${lc_info[0]} -Iseconds)"
	lc_line="${lc_info[*]:1}"

	# If last command is the same, avoid logging twice
	[ "$lc_line" == "$llc_line" ] && return

	iface="$(__x9_get_network_interface)"
	ipv4_cidr="$(__x9_get_network_interface_cidr)"

	query="INSERT INTO command (session_id, start_date, end_date, hostname, ipv4_cidr, username, cwd, command_line, return_code) VALUES ('${X9_SESSION_ID}', '${lc_date}', '$(date -Iseconds)', '$(hostnamectl hostname)', '${ipv4_cidr}', '${USER}', '${PWD}', '${lc_line//\'/\'\'}', ${ret})"

	sqlite3 "$X9_DATABASE" "$query"

	llc_line="$lc_line"

	# Preserve return code
	return $ret
}

[ -n "$PROMPT_COMMAND" ] && PROMPT_COMMAND="__x9_hook; ${PROMPT_COMMAND}" || PROMPT_COMMAND=__x9_hook

# If we are already inside X9's script session, prevent screen clearing and return (this will also
# affect other script sessions)
if lsof -watc script "$(tty)" 2>&1 > /dev/null; then
	alias clear=true
	bind -r "\C-l"
	return
fi

start_date="$(date +%s)"
session_name="${X9_SESSION_ID}_${start_date}"

tmp_dir="$(mktemp -d)" || return

script -qt"${tmp_dir}/timescript" "${tmp_dir}/typescript"

# Append end time to session name
session_name+="-$(date +%s)"

tar -C "$tmp_dir" -cJf "${X9_SESSION_ROOT}/${session_name}.txz" {time,type}script

query="INSERT INTO session (session_id, start_date, end_date) VALUES ('${X9_SESSION_ID}', '$(date -d @${start_date} -Iseconds)', '$(date -Iseconds)')"
sqlite3 "$X9_DATABASE" "$query" || sleep 5

rm -rf "$tmp_dir"
exit 0
