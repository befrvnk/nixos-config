# nav-tools

Adds pi's built-in `grep`, `find`, and `ls` tools as always-available extension tools.

Why this exists:
- plain `pi` only enables `read`, `bash`, `edit`, and `write` by default
- these navigation tools are a better default than shelling out through `bash`
- the extension keeps them active automatically on session start

Implementation notes:
- tools are created with pi's built-in tool factories for the current session `cwd`
- no custom rendering or behavior changes are added
- `bash` remains available for tasks that truly need shell semantics
