# ERPNext v16 Business Suite — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **ERPNext v16 Business Suite** (version label `v16` = ERPNext major, written as Frappe does: "v16") |
| Description | Accounting, inventory, sales and CRM in one ERP. Frappe with workers and scheduler. (83 chars) |
| Category | Other |
| Tags | erpnext, frappe, erp, accounting, inventory, crm, mariadb |
| User input at deploy | **None.** Administrator password and all database/Redis passwords are generated. |

**Listing change:** LISTINGS.md says "Accounting, inventory, **HR** and CRM…". HR and payroll live in the separate Frappe HR (`hrms`) app, which is not part of the official `frappe/erpnext` image this template uses, so "HR" was replaced by "sales" (ERPNext's selling module is included). Adding Frappe HR requires a custom image build (see Open questions).

## Base market template

- **`erpnext` "ERPNext"** (pipech image, 100 active) — most used, but ships version-15 from a community image, starts with `tail -f /dev/null` and needs a manual setup script run, MariaDB 10.6, Redis without passwords. Idea kept: everything that needs `sites/` in one container under supervisord (the only workable shape on Railway).
- `erpnext-v16` (thspacecode repo, no license) and `erp` (praveen repo, no license) — read for comparison only; nothing copied.
- `_upstream/pipech__erpnext-docker-debian` is MIT (Copyright (c) 2018 pipech): the supervisord-in-one-container approach for Railway is credited; no file was copied (this package builds on the official image instead of compiling a bench).

## Pinned versions

| Service | Image | Tag | Release date | Checked |
|---|---|---|---|---|
| ERPNext (built from `services/erpnext`) | `frappe/erpnext` | `v16.50.0` (Frappe 16.51.0 inside) | 2026-10-06 | 2026-10-10 |
| MariaDB | `mariadb` | `11.8.9` (LTS line used by frappe_docker) | 2026 | 2026-10-10 |
| redis-cache, redis-queue | `redis` | `8.2` | Railway base | 2026-10-10 |

`frappe/erpnext:v16.50.0` is the tag pinned in frappe_docker v4.0.1 `example.env` / `pwd.yml` (released 2026-10-09). v15 (`v15.122.0`) is still maintained but v16 is the current major. Upgrade path: change `ARG ERPNEXT_VERSION` in `services/erpnext/Dockerfile` (or set a service variable `ERPNEXT_VERSION`, which Railway passes as a build argument; same major) and redeploy; the entrypoint runs `bench --site all migrate` once when it sees the new version. Major upgrades (v16 → v17) follow Frappe's upgrade notes and a backup first.

## Architecture

```
Internet ──HTTPS──▶ ERPNext service (one container, supervisord, volume = sites/)
                     ├─ nginx :8080        static assets, /socket.io, proxy to gunicorn (official template)
                     ├─ gunicorn :8000     Frappe web/API (official start.sh)
                     ├─ socket.io :9000    realtime (node)
                     ├─ queue-short ×N     bench worker --queue short,default
                     ├─ queue-long ×N      bench worker --queue long,default,short
                     └─ scheduler          bench schedule
                     │
                     ├─▶ MariaDB      (site database)
                     ├─▶ redis-cache  (cache; no persistence, LRU)
                     └─▶ redis-queue  (RQ jobs + socket.io pub/sub; persisted)
```

**Why one container.** Every Frappe process reads and writes the bench `sites/` directory (site config, uploaded files, backups). Railway volumes attach to exactly one service, so the upstream compose split (backend, frontend, websocket, queue-short, queue-long, scheduler sharing a `sites` volume) cannot be reproduced. This image runs exactly those upstream processes, with the upstream commands, under supervisord in one service that owns the `sites` volume. MariaDB and both Redis instances stay separate services as upstream.

**Boot sequence** (`railway-entrypoint.sh` → `railway-bootstrap.sh`): fix volume ownership (Railway mounts it as root) → link the image's built assets and restore `apps.json`/`apps.txt` → write `common_site_config.json` from variables (every boot) → wait for MariaDB/Redis → on first boot `bench new-site … --install-app erpnext --set-default` + `enable-scheduler` (about 1.5 minutes in a local test) → set `host_name` → migrate once if the image version changed → start supervisord. A half-finished site creation is detected by marker files and retried cleanly; restored sites without markers are never touched. If any process keeps crashing, a supervisor event listener stops the container so Railway restarts it.

**Fixed site name.** The site is created as `erpnext.local` and nginx always serves it, whatever the Host header, so the Railway domain and any custom domains work without renaming the site. Frappe's socket.io checks that the `Origin` host equals the `Host` header; the official nginx template sets `Origin` to the site name, so the Dockerfile patches that one line to use the request host.

### Deviations from upstream compose (and why)

- One container instead of six (volume constraint, see above). Process commands are the upstream ones.
- `configurator` / `create-site` one-shot containers → bootstrap script at start (same `bench set-config` and `bench new-site` commands).
- nginx master runs as root with workers as `frappe` and 2 worker processes (upstream runs nginx as `frappe`; under supervisord a non-root nginx cannot write to the log pipes).
- Redis with passwords (Railway base) instead of open Redis; cache Redis without persistence and with LRU eviction.
- MariaDB listens on IPv4 and IPv6 (`--bind-address=*`; `::` alone is IPv6-only in MariaDB 11.8, verified locally).
- Worker process counts are variables instead of separate containers.

## Services

All services are created together from the template; references resolve at deploy time. Values are entered exactly as shown.

### ERPNext

- **Source:** GitHub repo `baranberkay96/erpnext-railway`, root directory `/services/erpnext` (Dockerfile build)
- **Start command:** image default
- **Healthcheck:** `/api/method/ping` (timeout 1200 s)
- **Public domain:** yes → target port `8080`
- **TCP proxy:** none
- **Volume:** `/home/frappe/frappe-bench/sites`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port nginx listens on inside the container (public domain target). |
| `SITE_NAME` | `erpnext.local` | Internal Frappe site name. Fixed on purpose: every domain pointed at this service serves this site. Must not equal an app name; do not change after first boot. |
| `PUBLIC_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL written to the site's host_name (links in e-mails, prints, background jobs). Update it with a custom domain. |
| `ADMIN_PASSWORD` | `${{secret(24)}}` | Password of the 'Administrator' user, used once when the site is created. Change it later inside ERPNext. |
| `DB_HOST` | `${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}` | MariaDB host (private network). |
| `DB_PORT` | `3306` | MariaDB port. |
| `DB_ROOT_PASSWORD` | `${{MariaDB.MARIADB_ROOT_PASSWORD}}` | MariaDB root password, used to create the site database and its user. |
| `REDIS_CACHE_URL` | `${{redis-cache.REDIS_URL}}` | Redis for Frappe's cache. |
| `REDIS_QUEUE_URL` | `${{redis-queue.REDIS_URL}}` | Redis for background job queues and socket.io pub/sub. |
| `GUNICORN_WORKERS` | `2` | Gunicorn worker processes (web requests). |
| `GUNICORN_THREADS` | `4` | Threads per Gunicorn worker. |
| `GUNICORN_TIMEOUT` | `120` | Seconds before a web request is killed. |
| `WORKER_SHORT_PROCS` | `1` | Background worker processes for the short/default queues. |
| `WORKER_LONG_PROCS` | `1` | Background worker processes for the long queue (imports, reposting, heavy reports). |
| `CLIENT_MAX_BODY_SIZE` | `50m` | Max upload size accepted by nginx. |
| `PROXY_READ_TIMEOUT` | `120` | nginx timeout (s) for slow reports and print formats. |
| `AUTO_MIGRATE` | `true` | Run 'bench --site all migrate' automatically once after the image version changes. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Give running background jobs time to finish on redeploy. |

### MariaDB

- **Source:** Docker image `mariadb:11.8.9`
- **Start command:** `/bin/sh -c "rm -rf /var/lib/mysql/lost+found && exec docker-entrypoint.sh mariadbd --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --skip-character-set-client-handshake '--bind-address=*' --innodb-buffer-pool-size=$MARIADB_INNODB_BUFFER_POOL_SIZE"`
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/var/lib/mysql`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `MARIADB_ROOT_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") }}` | Root password (generated). |
| `MARIADB_AUTO_UPGRADE` | `1` | Run mariadb-upgrade automatically after an image upgrade. |
| `MARIADB_INNODB_BUFFER_POOL_SIZE` | `512M` | InnoDB buffer pool (main memory knob). Raise it as the database grows. |
| `MARIADBHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private hostname. |
| `MARIADBPORT` | `3306` | Port. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow MariaDB to shut down cleanly. |

### redis-cache

- **Source:** Docker image `redis:8.2`
- **Start command:** `/bin/sh -c "exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save '' --appendonly no --maxmemory 256mb --maxmemory-policy allkeys-lru"`
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private hostname (cache only: no persistence, LRU eviction at 256 MB). |
| `REDISPORT` | `6379` | Port that Redis listens on. |
| `REDISUSER` | `default` | Username for authenticating with Redis. |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network. |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name. |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis. |

### redis-queue

- **Source:** Docker image `redis:8.2`
- **Start command:** `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH"`
- **Healthcheck:** none (no HTTP endpoint)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service, only resolvable from services in the same environment. |
| `REDISPORT` | `6379` | Port that Redis listens on. |
| `REDISUSER` | `default` | Username for authenticating with Redis. |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network. |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name. |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis. |

## Improvements over market templates

| # | Change | Why |
|---|---|---|
| 1 | Official `frappe/erpnext:v16.50.0` image as base (leader: community image, version-15) | Current major, official build, assets prebuilt; only supervisord added. |
| 2 | Site is created automatically on first boot with a generated Administrator password and the scheduler enabled (leader: `tail -f /dev/null`, manual setup script) | Deploy → log in. No shell access needed. |
| 3 | Automatic `bench migrate` once per image version (`AUTO_MIGRATE`) | Upgrades are a tag change + redeploy. |
| 4 | Retry-safe first boot (marker files) and crash watchdog (supervisor FATAL listener) | A failed first boot or a crash-looping process restarts cleanly instead of leaving a half-working container. |
| 5 | MariaDB 11.8.9 LTS (frappe_docker's version) with utf8mb4 settings, dual-stack bind, tunable buffer pool, `lost+found` removed, auto-upgrade | Matches upstream; works on IPv4 and IPv6 private networks. |
| 6 | Redis services with generated passwords; cache without persistence + LRU, queue persisted | Security and correct cache behaviour (leader: open Redis 6.2, cache had no eviction policy). |
| 7 | Healthcheck `/api/method/ping` through nginx | Railway only routes to a working site. |
| 8 | Fixed site name + socket.io Origin fix | Custom domains and the Railway domain work without renaming the site; realtime updates work. |
| 9 | Worker counts, Gunicorn sizing, upload size and timeouts as variables | Scale inside the container without editing files. |
| 10 | Tested end to end locally (empty root-owned volume, password-protected Redis): site creation, login, desk assets, socket.io namespace auth, background job, restart on existing volume, version-change migrate | Fewer surprises on first Railway deploy. |

## First login

1. Wait for the first deploy to turn healthy (site creation takes a few minutes; healthcheck timeout is 20 minutes).
2. Open the public URL, log in as **Administrator** with the `ADMIN_PASSWORD` value from the ERPNext service variables.
3. Complete the setup wizard (company, currency, fiscal year, chart of accounts). Change the Administrator password and create named users.
4. E-mail: configure an Email Account (SMTP/IMAP) in ERPNext (Settings → Email Account).

## Scaling

- Background load: raise `WORKER_LONG_PROCS` / `WORKER_SHORT_PROCS` (processes inside the container) and give the service more memory.
- Web load: raise `GUNICORN_WORKERS` / `GUNICORN_THREADS`.
- Horizontal replicas are **not** possible for the ERPNext service (it owns the `sites` volume). MariaDB: raise `MARIADB_INNODB_BUFFER_POOL_SIZE` with the data size.

## Backups

`bench --site erpnext.local backup --with-files` (Railway shell) writes to `sites/erpnext.local/private/backups` on the volume; download them from ERPNext (Settings → Backups) or copy them off-site. Railway volume backups cover the `sites` and MariaDB volumes.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Idle figures for ERPNext, MariaDB and Redis were measured locally right after boot (ERPNext 400 MB, MariaDB 300 MB with a 256 MB buffer pool, Redis 45 MB / 15 MB).

| Service | Idle RAM | Typical RAM (5–30 users) | Typical CPU |
|---|---|---|---|
| ERPNext (nginx, gunicorn 2×4, socket.io, 2 workers, scheduler) | 450 MB | 1.4 GB | 0.35 vCPU |
| MariaDB (512 MB buffer pool) | 400 MB | 700 MB | 0.15 vCPU |
| redis-cache | 45 MB | 150 MB | 0.01 vCPU |
| redis-queue | 15 MB | 30 MB | <0.01 vCPU |
| **Total** | **≈0.9 GB** (≈0.05 vCPU) | **≈2.3 GB** | **≈0.5 vCPU** |

- **Idle:** ≈ $9 RAM + $1 CPU + $0.5 volumes ≈ **$11/month**.
- **Typical:** ≈ $23 RAM + $10 CPU + $0.75 volumes (5 GB) ≈ **$34/month**.
- **Minimum plan:** Hobby. The ERPNext service needs more than Trial's 1 GB under normal use, and the image build is large.

## Verification checklist

- [ ] ERPNext build succeeds (Dockerfile build from `services/erpnext`; the base image is about 2 GB).
- [ ] First-boot logs: `[railway-bootstrap] Creating site erpnext.local …` → `Site erpnext.local created` → `Starting supervisord`; deployment healthy on `/api/method/ping`.
- [ ] Log in as Administrator, finish the setup wizard, create an Item and a Sales Invoice, print it (PDF).
- [ ] Realtime: open a document in two tabs, change it in one → the other shows "document has been modified" (socket.io).
- [ ] Background jobs: run a Data Import of a few Customers → completes (queue-long); logs show `Job OK`.
- [ ] Redeploy ERPNext: logs show `Bootstrap finished` without creating a site; data and attached files persist.
- [ ] Upgrade test: set a service variable `ERPNEXT_VERSION` to a newer v16 tag (Railway passes it to the Dockerfile `ARG`) → logs show `running bench migrate` once.

## Open questions

- **Frappe HR (payroll, leave, attendance)** is not included; it needs a custom image built with `frappe/hrms` (frappe_docker "custom image" / `apps.json` build). Not done here because the build is heavy and was not verified on Railway's builder.
- **Healthcheck timeout:** first boot needs a few minutes for site creation; the template sets 1200 s. Confirm Railway accepts this value for the healthcheck timeout.
- **Railway build:** the build pulls `frappe/erpnext` (~2 GB compressed layers) and installs supervisor; first build time on Railway not measured.
- **Socket.io on Railway:** the auth step makes the realtime server call `https://<public domain>/api/method/frappe.realtime.get_user_info` through Railway's edge (upstream behaviour). Verified locally with a port-80 setup; confirm on Railway with the two-tab test.
