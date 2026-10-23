# One more cup

A focus timer and personal task list. Pick a task, focus for 15, 25 or 45 minutes, then take a 5- or 15-minute break. At the end, a completion card offers the next step. Browser notifications are optional.

**Stack:** plain HTML, CSS and JavaScript ES modules, served by unprivileged Nginx. No npm dependencies, build framework, backend or database. Source is in `dist/`; these are editable files, not generated bundles. A multi-stage build would add no useful compilation stage, so the Dockerfile uses a single runtime stage.

## Try the source without Docker

From the project folder:

```bash
python3 -m http.server 8888 --bind 127.0.0.1 --directory dist
```

Open **http://localhost:8888/**. The checked-in `dist/version.json` selects v2 for this local preview. Stop with Ctrl+C. Python is only a development convenience and is not used in the image.

## Build two linux/amd64 images

Install Docker with Buildx on your own machine. No credentials are needed for the local build. Choose a public Docker Hub repository if you intend to use the app for IoT p3; replace `YOUR_DOCKERHUB_USERNAME` below.

```bash
export CUP_IMAGE=docker.io/YOUR_DOCKERHUB_USERNAME/one-more-cup

docker buildx build --platform linux/amd64 --load \
  --build-arg APP_VERSION=v1 -t "$CUP_IMAGE:v1" .

docker buildx build --platform linux/amd64 --load \
  --build-arg APP_VERSION=v2 -t "$CUP_IMAGE:v2" .
```

`APP_VERSION` is resolved at build time by copying the matching `releases/v1.json` or `releases/v2.json`. Unsupported values fail the build. Version v1 is green / first brew; v2 is terracotta / slow roast. Both provide all timer, task and notification features. The UI badge and `/version.json` show the built version. Passing `-e APP_VERSION=v2` when running a v1 image does not change its version.

The runtime base is pinned to `nginx/nginx-unprivileged:1.30.6-alpine3.24`, a concrete stable Nginx and Alpine release. This is a version pin, not an immutable digest lock; you may additionally pin a verified digest after pulling the image in your environment. Do not use `latest` for the application.

### Run and verify v1

```bash
docker run --rm -d --name cup-v1 --platform linux/amd64 \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=32m \
  -p 127.0.0.1:8888:8888 "$CUP_IMAGE:v1"

curl -fsS http://localhost:8888/healthz
curl -fsS http://localhost:8888/version.json
curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:8888/
```

Expected: `ok`, `{"version":"v1"}` and `200`. Open http://localhost:8888/ to inspect the green theme. The container listens on **0.0.0.0:8888**; the example binds the host port to loopback.

```bash
docker stop cup-v1
```

### Run and verify v2

```bash
docker run --rm -d --name cup-v2 --platform linux/amd64 \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=32m \
  -p 127.0.0.1:8888:8888 "$CUP_IMAGE:v2"

curl -fsS http://localhost:8888/healthz
curl -fsS http://localhost:8888/version.json
curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:8888/
```

Expected: `ok`, `{"version":"v2"}` and `200`. Refresh the browser to inspect the terracotta theme.

```bash
docker stop cup-v2
```

There are no client-side routes. `/` and `/index.html` load the app; reloading `/` works. Unknown URLs return 404 instead of incorrectly serving HTML as JSON or JavaScript. A future client-side router would require revisiting the Nginx fallback.

The image runs as UID/GID 101 and uses one Nginx worker to keep the small memory limit reasonable. Only `dist/`, the selected release JSON and Nginx server configuration are copied into it. The allowlist in `.dockerignore` excludes Git history, credentials, tests, docs, node_modules and development files. Nginx needs a writable `/tmp`; the rest can be read-only. `/healthz` is an HTTP 200 response served by Nginx, not an application or database health check.

An optional reproducible local smoke check is provided for each image:

```bash
sh scripts/smoke-container.sh "$CUP_IMAGE:v1" v1 8888
sh scripts/smoke-container.sh "$CUP_IMAGE:v2" v2 8888
```

It runs and removes a temporary container, checks HTML, module content type, health, version, unknown-path 404 and the non-root UID. It requires Docker, curl and Python 3. It does not publish anything.

## Notifications

Click **Enable notifications** to request permission. Loading or reloading the page never requests it. If permission is already granted, **Send a test notification** checks delivery. Dismissing a prompt leaves permission unrequested; a denied permission is not requested again. Use the browser's site settings if you later want to allow it.

The app checks the browser's current permission on completion, window focus and tab return. It does not persist an independent permission flag that could become stale. Unsupported browsers, insecure contexts, denied permission and delivery failures are handled. The completion card always appears, including when a system notification cannot be shown. Completion messages identify the period and suggest a next step. A session can complete only once; notification IDs also suppress repeated attempts for that completion.

Use **HTTPS**, or a browser-supported **http://localhost** / loopback context. Plain HTTP on a VM IP or a custom hostname normally cannot request notifications. For local Kubernetes tests, run port-forward on the computer running your browser or use an SSH tunnel and open localhost there. Do not disable browser security. OS Do Not Disturb, system settings, private browsing, iframe restrictions and platform support can prevent visible banners even after permission is granted.

The app first uses the Web Notifications constructor. On mobile platforms that require it, a small service worker provides `showNotification()` as a fallback. That worker does not cache the app, schedule timers or receive Push messages. Not all mobile platforms support permission requests from ordinary browser tabs; some require an installed web app, which is not provided here. The in-page result remains available.

**Keep the page open.** Remaining time is calculated from a `Date.now()` deadline, not a count of interval callbacks. A throttled background tab catches up when JavaScript runs again or when you return. Delivery may be late while the browser suspends a tab or the computer sleeps. Adjusting the device clock may change the remaining time. Reloading starts a fresh timer; it preserves tasks and focus-duration preferences.

**After closing the page:** this implementation cannot guarantee any timer execution or notification. Reliable closed-page delivery would require a server-side scheduler and durable session storage, Web Push subscriptions, a push service and push handling in a service worker, plus user permission and supported HTTPS delivery. A service worker by itself is not a reliable alarm clock. Those server and Push components are intentionally not implemented.

## Data and privacy

Tasks, your chosen focus duration and today's completed focus count are stored in browser **localStorage**, scoped to the origin (scheme + hostname + port). They are not shared between visitors or devices. Containers and Kubernetes PVCs do not store or synchronize them. Changing port, hostname or scheme creates a different browser storage origin. Switching Docker image versions at the same origin keeps the data. Private browsing and storage errors can prevent persistence; the app displays a warning and continues for the current page session.

No analytics, login, external notification service or network backend is included. Fonts use the system stack so the application does not need an external font service. No project license file is included. The base image retains its upstream licensing metadata.

## Publishing to Docker Hub

Create a **public** Docker Hub repository named `one-more-cup` under your account. Keep the same `CUP_IMAGE` value used for both local builds. Sign in interactively; do not put a password or access token in a command or commit it to the project.

```bash
# From this application directory, after both local smoke checks pass:
export CUP_IMAGE=docker.io/YOUR_DOCKERHUB_USERNAME/one-more-cup
docker login -u YOUR_DOCKERHUB_USERNAME
docker push "$CUP_IMAGE:v1"
docker push "$CUP_IMAGE:v2"
```

Check that both tags appear in the public Docker Hub repository. The `v1` and `v2` tags should identify the tested images; avoid overwriting them later. Kubernetes normally pulls a public image on the node through its container runtime after a Git-managed Deployment image change. Running `docker pull` on the build machine does not load the image into a separate K3d node.

The IoT repository already owns its `p3` and `bonus` Kubernetes configuration. Keep the existing Argo CD Application and `playground` Deployment/Service there; change the Deployment image in the Git source selected for the demonstration. The image built here contains only the static app and Nginx configuration.

## Tests and verification

No npm installation is needed. For the automated tests, use a current Node.js with the built-in test runner (Node is a development tool only):

```bash
node --test tests/*.test.mjs
node --input-type=module --check < dist/app.js
node --check dist/sw.js
```

Timer tests inject a clock; notification tests use explicit permission/API mocks. They test background catch-up, pause/resume, multiple ticks at zero, new sessions, denied/default/granted/unsupported/insecure states, changed permission, duplicate sends and constructor/worker failures. Mocks do not prove a real OS banner was delivered.

The Node tests cover timer timing, notification states and the main app flow with a small DOM fixture. Also check the UI and browser notifications manually in a real browser.
