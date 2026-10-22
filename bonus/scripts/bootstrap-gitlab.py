#!/usr/bin/env python3

import getpass
import json
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

API_URL = "http://localhost:8080/api/v4"
SEED_DIR = Path(__file__).resolve().parent.parent / "confs/application"


def api(token, method, path, payload=None, allow_missing=False):
    headers = {"PRIVATE-TOKEN": token}
    data = None

    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")

    request = Request(
        f"{API_URL}{path}",
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urlopen(request, timeout=60) as response:
            return json.load(response)
    except HTTPError as error:
        if allow_missing and error.code == 404:
            return None
        raise RuntimeError(
            f"{method} {path}: HTTP {error.code}"
        ) from error


def main():
    # Read both files before making any changes in GitLab.
    actions = [
        {
            "action": "create",
            "file_path": name,
            "content": (SEED_DIR / name).read_text(encoding="utf-8"),
        }
        for name in ("deployment.yaml", "service.yaml")
    ]

    token = getpass.getpass("GitLab API token: ")
    if not token:
        raise RuntimeError("Token must not be empty.")

    user = api(token, "GET", "/user")
    print(f"Authenticated as: {user['username']}")

    group = api(token, "GET", "/groups/osivkov", allow_missing=True)
    if group is None:
        group = api(token, "POST", "/groups", {
            "name": "osivkov",
            "path": "osivkov",
            "visibility": "public",
        })
        print("Created group: osivkov")
    else:
        print("Group already exists: osivkov")

    project_path = quote("osivkov/iot", safe="")
    project = api(
        token, "GET", f"/projects/{project_path}", allow_missing=True
    )

    if project is None:
        project = api(token, "POST", "/projects", {
            "name": "iot",
            "path": "iot",
            "namespace_id": group["id"],
            "visibility": "public",
            "initialize_with_readme": False,
        })
        print("Created project: osivkov/iot")
    else:
        print("Project already exists: osivkov/iot")

    if project["visibility"] != "public":
        raise RuntimeError(
            "Project must be public for our anonymous Argo CD access."
        )

    if not project["empty_repo"]:
        print("Repository already contains commits; leaving it unchanged.")
        return

    api(token, "POST", f"/projects/{project['id']}/repository/commits", {
        "branch": "main",
        "commit_message": "feat: add playground deployment and service",
        "actions": actions,
    })
    print("Created initial commit on main with both application manifests.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, URLError, OSError, ValueError, KeyError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)