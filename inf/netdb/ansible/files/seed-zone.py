#!/usr/bin/env python3
"""Idempotently seed netdb so it's authoritative for the delegated zone.

Steps (all via netdb's MCP JSON-RPC at http://127.0.0.1:8080/mcp):
  1. ensure a 'technitium' DNS provider row exists (its URL/token come from
     env in netdb — config_json stays empty)
  2. ensure a forward zone for <zone> exists
  3. link the zone to the provider so the reconciler pushes records to
     Technitium → resolvable under the delegated zone.

Best-effort + idempotent: re-running is a no-op. If anything is already set
up (or netdb returns an error on a duplicate), we tolerate it and move on.
The same thing can be done live through the Olympus agent / netdb UI.

Usage: seed-zone.py <zone>   e.g. seed-zone.py lab.0lympu5.com
"""
import json
import sys
import urllib.request

MCP = "http://127.0.0.1:8080/mcp"


def call(name, arguments=None):
    """One MCP tools/call. Returns the tool's output parsed from the
    text-content envelope, or None on any failure."""
    payload = {
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": name, "arguments": arguments or {}},
    }
    req = urllib.request.Request(
        MCP, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            env = json.loads(r.read())
    except Exception as e:  # noqa: BLE001
        print(f"  ! {name} request failed: {e}")
        return None
    try:
        text = env["result"]["content"][0]["text"]
        return json.loads(text)
    except Exception:  # tool error or non-JSON text — surface it, treat as None
        print(f"  ! {name} -> {json.dumps(env)[:200]}")
        return None


def _ci(obj):
    """Case-insensitive key view of a dict (netdb marshals PascalCase:
    ID/Name/Kind), else empty."""
    return {k.lower(): v for k, v in obj.items()} if isinstance(obj, dict) else {}


def obj_id(obj):
    return _ci(obj).get("id")


def find_id(items, **match):
    """Find the id of the first item matching all key=value pairs. Keys + the
    id field are matched case-insensitively (netdb returns ID/Name/Kind)."""
    for it in (items or []):
        lit = _ci(it)
        if all(str(lit.get(k.lower(), "")).lower() == str(v).lower() for k, v in match.items()):
            if lit.get("id") is not None:
                return lit["id"]
    return None


def main():
    zone = sys.argv[1] if len(sys.argv) > 1 else "lab.0lympu5.com"

    # 1. Technitium provider
    providers = call("list_providers")
    pid = find_id(providers, kind="technitium")
    if pid is None:
        print("  creating technitium provider")
        out = call("create_provider", {"name": "technitium", "kind": "technitium", "enabled": True})
        pid = obj_id(out)
    print(f"  provider id = {pid}")

    # 2. Forward zone
    zones = call("list_zones")
    zid = find_id(zones, name=zone)
    if zid is None:
        print(f"  creating zone {zone}")
        out = call("create_zone", {"name": zone, "kind": "forward",
                                    "description": "Olympus demo - agent-managed"})
        zid = obj_id(out)
    print(f"  zone id = {zid}")

    # 3. Link
    if pid is not None and zid is not None:
        print("  linking zone -> provider")
        call("link_zone_provider", {"zone_id": zid, "provider_id": pid})
        call("dns_sync_now")
        print("created/linked OK")
    else:
        print("  ! could not resolve provider/zone ids — seed via the agent or netdb UI")


if __name__ == "__main__":
    main()
