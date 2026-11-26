#!/usr/bin/env -S uv run --quiet --with pyjwt --with cryptography --with certifi python
"""Wait for a processed build of <bundle> and put it on a beta group, then report what Apple says.

    scripts/asc-attach-build.py com.example.app <beta group id>

Prints the build it attached and exits 0, or prints what it is waiting for and exits 1. The API
key comes from APP_STORE_CONNECT_API_KEY{,_ID} and APP_STORE_CONNECT_API_ISSUER_ID, the same
variables the rest of the Galatea iOS lanes use. Nothing here prints key material.
"""
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

import certifi
import jwt

KEY_ID = os.environ["APP_STORE_CONNECT_API_KEY_ID"]
ISSUER = os.environ["APP_STORE_CONNECT_API_ISSUER_ID"]
KEY = open(
    os.environ.get(
        "APP_STORE_CONNECT_API_KEY_PATH",
        os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"),
    )
).read()
CTX = ssl.create_default_context(cafile=certifi.where())


def call(method, path, body=None):
    token = jwt.encode(
        {
            "iss": ISSUER,
            "iat": int(time.time()),
            "exp": int(time.time()) + 900,
            "aud": "appstoreconnect-v1",
        },
        KEY,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, context=CTX, timeout=90) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def main(bundle, group):
    status, apps = call("GET", f"/v1/apps?filter[bundleId]={bundle}")
    if status != 200 or not apps["data"]:
        print(f"no app record for {bundle} (status {status})")
        return 1
    app = apps["data"][0]["id"]

    status, builds = call(
        "GET",
        f"/v1/builds?filter[app]={app}&fields[builds]=version,processingState,uploadedDate",
    )
    ready = [b for b in builds["data"] if b["attributes"]["processingState"] == "VALID"]
    if status != 200 or not ready:
        states = [b["attributes"]["processingState"] for b in builds["data"]]
        print(f"no VALID build yet (states {states or 'none'})")
        return 1
    ready.sort(key=lambda b: int(b["attributes"]["version"]))
    build = ready[-1]

    status, _ = call(
        "POST",
        f"/v1/betaGroups/{group}/relationships/builds",
        {"data": [{"type": "builds", "id": build["id"]}]},
    )
    if status >= 400:
        print(f"attach refused ({status})")
        return 1

    # Read every claim back rather than reporting the write.
    _, group_builds = call("GET", f"/v1/betaGroups/{group}/builds?fields[builds]=version,processingState")
    _, detail = call("GET", f"/v1/builds/{build['id']}/buildBetaDetail")
    _, testers = call("GET", f"/v1/betaGroups/{group}/betaTesters?fields[betaTesters]=email,state")
    on_group = [b["attributes"]["version"] for b in group_builds["data"]]
    print(f"build {build['attributes']['version']} ({build['id']}) is on the group: {on_group}")
    print(f"internal build state: {detail['data']['attributes']['internalBuildState']}")
    print("testers: " + ", ".join(f"{t['attributes'].get('email')}={t['attributes'].get('state')}" for t in testers["data"]))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    sys.exit(main(sys.argv[1], sys.argv[2]))
