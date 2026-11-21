#!/usr/bin/env python3
"""Small App Store Connect API client used by CI (standard library + openssl only).

Auth comes from the environment:
  ASC_KEY_ID      API key ID, e.g. YL7475HMQ3
  ASC_ISSUER_ID   issuer ID (UUID)
  ASC_KEY_PATH    path to the AuthKey_<id>.p8 file

Commands:
  register-bundle-id IDENTIFIER NAME      create the bundle ID if it does not exist
  app-id BUNDLE_ID                        print the App Store Connect app id
  next-build-number BUNDLE_ID             print (highest uploaded build number) + 1
  wait-build BUNDLE_ID VERSION BUILD      wait until the build has processed, print its id
  set-whats-new BUILD_ID FILE [LOCALE]    set the TestFlight "What to Test" text
  ensure-group BUNDLE_ID NAME             ensure an internal beta group that gets every build
  add-to-group BUILD_ID GROUP_NAME        add a build to a (external) beta group
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_to_raw(der: bytes) -> bytes:
    # ECDSA signature DER (30 len 02 lr r 02 ls s) -> raw r||s, 32 bytes each.
    i = 2
    if der[1] & 0x80:
        i += der[1] & 0x7F
    assert der[i] == 2
    lr = der[i + 1]
    r = der[i + 2:i + 2 + lr]
    i += 2 + lr
    assert der[i] == 2
    ls = der[i + 1]
    s = der[i + 2:i + 2 + ls]
    return r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")


_token = {"value": None, "exp": 0}


def token() -> str:
    now = int(time.time())
    if _token["value"] and now < _token["exp"] - 60:
        return _token["value"]
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    key_path = os.path.expanduser(os.environ["ASC_KEY_PATH"])
    exp = now + 15 * 60
    header = _b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = _b64(json.dumps({"iss": issuer, "iat": now, "exp": exp, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    _token["value"] = f"{header}.{payload}.{_b64(_der_to_raw(der))}"
    _token["exp"] = exp
    return _token["value"]


def call(method: str, path: str, body=None, query=None):
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"App Store Connect API {method} {path} failed: HTTP {e.code}\n{detail}")


def log(msg: str):
    print(msg, file=sys.stderr, flush=True)


def app_id(bundle_id: str) -> str:
    res = call("GET", "/v1/apps", query={"filter[bundleId]": bundle_id, "fields[apps]": "bundleId"})
    apps = [a for a in res.get("data", []) if a["attributes"]["bundleId"] == bundle_id]
    if not apps:
        raise SystemExit(f"No App Store Connect app with bundle ID {bundle_id}. Create the app record first.")
    return apps[0]["id"]


def cmd_register_bundle_id(identifier: str, name: str):
    res = call("GET", "/v1/bundleIds", query={"filter[identifier]": identifier})
    for b in res.get("data", []):
        if b["attributes"]["identifier"] == identifier:
            log(f"Bundle ID {identifier} already registered ({b['id']}).")
            print(b["id"])
            return
    res = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}})
    log(f"Registered bundle ID {identifier}.")
    print(res["data"]["id"])


def cmd_app_id(bundle_id: str):
    print(app_id(bundle_id))


def cmd_next_build_number(bundle_id: str):
    aid = app_id(bundle_id)
    highest = 0
    path, query = "/v1/builds", {"filter[app]": aid, "fields[builds]": "version", "limit": "200"}
    while path:
        res = call("GET", path, query=query)
        for b in res.get("data", []):
            try:
                highest = max(highest, int(b["attributes"]["version"]))
            except ValueError:
                pass
        nxt = res.get("links", {}).get("next")
        path, query = (nxt.replace(API, ""), None) if nxt else (None, None)
    print(highest + 1)


def cmd_wait_build(bundle_id: str, version: str, build: str, timeout_min: str = "45"):
    aid = app_id(bundle_id)
    deadline = time.time() + int(timeout_min) * 60
    while time.time() < deadline:
        res = call("GET", "/v1/builds", query={
            "filter[app]": aid, "filter[version]": build,
            "filter[preReleaseVersion.version]": version,
            "fields[builds]": "version,processingState",
        })
        if res.get("data"):
            b = res["data"][0]
            state = b["attributes"]["processingState"]
            log(f"Build {version} ({build}): {state}")
            if state == "VALID":
                print(b["id"])
                return
            if state in ("FAILED", "INVALID"):
                raise SystemExit(f"Build {version} ({build}) processing ended as {state}.")
        else:
            log(f"Build {version} ({build}) not visible yet...")
        time.sleep(30)
    raise SystemExit(f"Timed out waiting for build {version} ({build}) to process.")


def cmd_set_whats_new(build_id: str, file: str, locale: str = "en-US"):
    with open(file, encoding="utf-8") as f:
        text = f.read().strip()[:4000]
    res = call("GET", f"/v1/builds/{build_id}/betaBuildLocalizations")
    for loc in res.get("data", []):
        if loc["attributes"]["locale"] == locale:
            call("PATCH", f"/v1/betaBuildLocalizations/{loc['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
            log(f"Updated What to Test ({locale}).")
            return
    call("POST", "/v1/betaBuildLocalizations", {"data": {
        "type": "betaBuildLocalizations",
        "attributes": {"locale": locale, "whatsNew": text},
        "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    log(f"Set What to Test ({locale}).")


def _group(aid: str, name: str):
    res = call("GET", "/v1/betaGroups", query={"filter[app]": aid, "filter[name]": name})
    for g in res.get("data", []):
        if g["attributes"]["name"] == name:
            return g
    return None


def cmd_ensure_group(bundle_id: str, name: str):
    aid = app_id(bundle_id)
    g = _group(aid, name)
    if g:
        log(f"Beta group '{name}' exists ({g['id']}).")
    else:
        g = call("POST", "/v1/betaGroups", {"data": {
            "type": "betaGroups",
            "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
        log(f"Created internal beta group '{name}' ({g['id']}).")
    print(g["id"])


def cmd_add_to_group(build_id: str, group_name: str):
    b = call("GET", f"/v1/builds/{build_id}/app")
    g = _group(b["data"]["id"], group_name)
    if not g:
        raise SystemExit(f"No beta group named '{group_name}'.")
    if g["attributes"].get("isInternalGroup") and g["attributes"].get("hasAccessToAllBuilds"):
        log(f"'{group_name}' already receives every build.")
        return
    call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds",
         {"data": [{"type": "builds", "id": build_id}]})
    log(f"Added build to '{group_name}'.")


COMMANDS = {
    "register-bundle-id": cmd_register_bundle_id,
    "app-id": cmd_app_id,
    "next-build-number": cmd_next_build_number,
    "wait-build": cmd_wait_build,
    "set-whats-new": cmd_set_whats_new,
    "ensure-group": cmd_ensure_group,
    "add-to-group": cmd_add_to_group,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    COMMANDS[sys.argv[1]](*sys.argv[2:])
