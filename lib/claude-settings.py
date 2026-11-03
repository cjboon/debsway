"""claude-settings.py add|remove SETTINGS WREN_JSON STATE: puts Wren Linux's
Claude Code settings (WREN_JSON) into your SETTINGS (~/.claude/settings.json)
or takes them out again, for extras/claude-regular.sh. Lists get Wren Linux's
items added to yours; a value (like sandbox.enabled) is set only if you haven't
set it yourself. STATE remembers exactly what was added, so remove takes out
that and nothing of yours. Run with python3 -I."""
import json
import os
import sys


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def save(path, data, mode=0o600):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".wren-tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def add(mine, ours, path, added):
    for key, value in ours.items():
        where = path + [key]
        if isinstance(value, dict):
            if not isinstance(mine.get(key), dict):
                if key in mine:
                    continue  # yours is something else: left alone
                mine[key] = {}
            add(mine[key], value, where, added)
        elif isinstance(value, list):
            have = mine.setdefault(key, [])
            if not isinstance(have, list):
                continue
            for item in value:
                if item not in have:
                    have.append(item)
                    added.append({"path": where, "item": item})
        elif key not in mine:
            mine[key] = value
            added.append({"path": where, "value": value})


def remove(mine, added):
    for a in added:
        node = mine
        for key in a["path"][:-1]:
            node = node.get(key) if isinstance(node, dict) else None
            if node is None:
                break
        if not isinstance(node, dict):
            continue
        last = a["path"][-1]
        if "item" in a and isinstance(node.get(last), list) and a["item"] in node[last]:
            node[last].remove(a["item"])
        elif "value" in a and node.get(last) == a["value"]:
            del node[last]
    prune(mine)


def prune(node):
    """Empty lists and objects Wren Linux's removal left behind go too."""
    for key in list(node):
        if isinstance(node[key], dict):
            prune(node[key])
        if node[key] in ({}, []):
            del node[key]


def main():
    action, settings, ours_path, state = sys.argv[1:5]
    mine = load(settings, {})
    if not isinstance(mine, dict):
        sys.exit("%s isn't a JSON object; leaving it alone." % settings)
    if action == "add":
        added = load(state, [])
        add(mine, load(ours_path, {}), [], added)
        save(settings, mine)
        save(state, added)
    elif action == "remove":
        remove(mine, load(state, []))
        save(settings, mine)
        if os.path.exists(state):
            os.remove(state)
    else:
        sys.exit("usage: claude-settings.py add|remove SETTINGS WREN_JSON STATE")


main()
