# NOTICE — ERPNext v16 Business Suite

## Software deployed (not redistributed)

| Component | Source | License |
|---|---|---|
| ERPNext | `frappe/erpnext:v16.50.0` (built by frappe/frappe_docker) — https://github.com/frappe/erpnext | GPL-3.0 |
| Frappe Framework | included in the image — https://github.com/frappe/frappe | MIT |
| Supervisor | Debian package installed at build time | BSD-derived (Repoze) license |
| MariaDB | `mariadb:11.8.9` | GPL-2.0 |
| Redis | `redis:8.2` (Railway base definition) | Redis 8 tri-license (RSALv2 / SSPLv1 / AGPLv3) |

## Upstream files checked (2026-10-10)

- `frappe/frappe_docker` tag `v4.0.1`: `pwd.yml`, `example.env`, `images/production/Containerfile`, `resources/core/main-entrypoint.sh`, `resources/core/start.sh`, `resources/core/nginx/nginx-entrypoint.sh`, `resources/core/nginx/nginx-template.conf`.
- `frappe/frappe` branch `version-16`: `frappe/utils/connections.py` (IPv6-aware connection checks), `frappe/utils/background_jobs.py`, `frappe/utils/redis_queue.py`, `node_utils.js`, `realtime/middlewares/authenticate.js` (Host/Origin check that motivated the nginx patch).

## Adapted material

- **frappe/frappe_docker** — MIT License, Copyright (c) 2017 Frappe Technologies Pvt. Ltd.
  The process list and commands in `services/erpnext/supervisord.conf.template` (`start.sh`, `node …/socketio.js`, `bench worker --queue …`, `bench schedule`, `nginx-entrypoint.sh`) and the configuration / site-creation commands in `railway-bootstrap.sh` (`bench set-config -g …`, `bench new-site --mariadb-user-host-login-scope='%' … --install-app erpnext --set-default`, assets symlink) follow frappe_docker's `pwd.yml` and entrypoint scripts. The official nginx template and entrypoints are used from the image; the Dockerfile changes one line of the template (socket.io `Origin`) with `sed`.
- **pipech/erpnext-docker-debian** (`_upstream/pipech__erpnext-docker-debian`) — MIT License, Copyright (c) 2018 pipech.
  Credited for the approach of running all Frappe processes under supervisord in one Railway service. No files were copied; this package builds on the official image instead.

## Not used

- `_upstream/thspacecode__erpnext-docker` and `_upstream/praveen-ks-2001__erpnext-railway`: no license (all rights reserved). Read for comparison only; nothing copied.
- Market templates `erpnext`, `erpnext-v16`, `erp`: no license; service layout compared only. All prose and descriptions here are original.
