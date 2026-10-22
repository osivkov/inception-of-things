#!/usr/bin/env python3

import getpass
import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

API_URL = "http://localhost:8080/api/v4"
GROUP_PATH = os.environ.get("GITLAB_GROUP", "osivkov")
PROJECT_PATH = os.environ.get("GITLAB_PROJECT", "iot")
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
    # Validate names and read seed files before changing GitLab.
    if not GROUP_PATH or not PROJECT_PATH:
        raise RuntimeError("Group and project paths must not be empty.")

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

    # Verify authentication.
    user = api(token, "GET", "/user")
    print(f"Authenticated as: {user['username']}")

    # Find or create the group.
    encoded_group = quote(GROUP_PATH, safe="")
    group = api(
        token,
        "GET",
        f"/groups/{encoded_group}",
        allow_missing=True,
    )

    if group is None:
        group = api(token, "POST", "/groups", {
            "name": GROUP_PATH,
            "path": GROUP_PATH,
            "visibility": "public",
        })
        print(f"Created group: {GROUP_PATH}")
    else:
        print(f"Group already exists: {GROUP_PATH}")

    if group["visibility"] != "public":
        raise RuntimeError(
            f"Group {GROUP_PATH} must be public for this setup."
        )

    # Find or create the project.
    full_path = f"{GROUP_PATH}/{PROJECT_PATH}"
    encoded_project = quote(full_path, safe="")
    project = api(
        token,
        "GET",
        f"/projects/{encoded_project}",
        allow_missing=True,
    )

    if project is None:
        project = api(token, "POST", "/projects", {
            "name": PROJECT_PATH,
            "path": PROJECT_PATH,
            "namespace_id": group["id"],
            "visibility": "public",
            "initialize_with_readme": False,
        })
        print(f"Created project: {full_path}")
    else:
        print(f"Project already exists: {full_path}")

    if project["visibility"] != "public":
        raise RuntimeError(
            f"Project {full_path} must be public for anonymous Argo CD access."
        )

    # Preserve any existing repository contents.
    if not project["empty_repo"]:
        print("Repository already contains commits; leaving it unchanged.")
        return

    # Add both manifests in the first commit.
    api(
        token,
        "POST",
        f"/projects/{project['id']}/repository/commits",
        {
            "branch": "main",
            "commit_message": "feat: add playground deployment and service",
            "actions": actions,
        },
    )
    print("Created initial commit on main with both application manifests.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, URLError, OSError, ValueError, KeyError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)