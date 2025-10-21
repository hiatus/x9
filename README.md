# X9

X9 is a simple system for logging commands with contextual information and raw terminal sessions using `script` and a `sqlite3` database. It works by hooking `PROMPT_COMMAND` with a logging handler. X9 will create a directory at `${HOME}/.local/share/x9` containing a SQLite database called `x9.db` as well as a directory called `session` for storing script sessions along with their timing information in compressed tar archives.

Note that this solution is not meant for secure auditing; that would be much better achieved by using something like `auditd`. The purpose of this is to be a simple solution for situations where we need to store detailed contextual information along with executed commands and full terminal sessions.

Each command will be saved with the following information:

```json
{
    "command_id": "d4612864-aa11-4998-b30b-37bf4514b39e",
    "session_id": "59e855c8-1694-450e-8144-1f8f8fdd75c4",
    "start_date": "2025-09-03T21:06:39-00:00",
    "end_date": "2025-09-03T21:06:39-00:00",
    "hostname": "MACHINE01",
    "ipv4_cidr": "10.17.98.4/23",
    "username": "hiatus",
    "cwd": "/home/hiatus",
    "command_line": "ls",
    "return_code": 0
}
```

The `session-id` can be then used to review the session on which the command occurred or to simply get information on the session. Sessions are saved with the following information:

```json
{
    "session_id": "59e855c8-1694-450e-8144-1f8f8fdd75c4",
    "start_date": "2025-09-03T21:05:59-00:00",
    "end_date": "2025-09-03T21:09:12-00:00",
}
```

## Installation

The following dependencies must be installed: `script`, `jq`, `sqlite3` and `uuidgen`.

To use X9, simply source `x9.bash` inside `~/.bashrc`. Note, though, that because X9 will enter a script session and call `exit` afterwards, importing `x9.bash` should be the last statement on `~/.bashrc`, as everything after it will be ignored, given that the shell will simply exit after the script session started by X9 logs out.

## Helper Functions

Some helpers are defined in `x9.bash` to facilitate searching through the database and viewing recorded sessions more easily:

- `x9-find-command [search-term]`: print the JSON of the command objects on the database whose `command_line` field contain `search-term`.
- `x9-find-session [substring-of-session-id]`: print the JSON of the session objects on the database whose `session-id` contains `substring-of-session-id`.
- `x9-session [print|play] [session-id]`: given a `session-id`, wither `print` the session contents to the terminal or `play` it back in real time.
