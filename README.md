# Deploy and Host ERPNext with Railway

ERPNext is an open-source ERP built on the Frappe framework, covering accounting, inventory, selling, buying, manufacturing, projects and CRM. This community template deploys ERPNext v16 from the official Frappe image on Railway with MariaDB, separate cache and queue Redis, background workers and the scheduler, and creates your site automatically.

## About Hosting ERPNext

An ERPNext install consists of a Gunicorn web server, a socket.io realtime server, background workers for short and long jobs, a scheduler, and nginx for static assets, plus MariaDB and two Redis instances. All Frappe processes must share the same `sites` folder, and a Railway volume belongs to a single service, so this template runs those processes together under supervisord in one service that owns the `sites` volume, while MariaDB and Redis run as their own services. On first boot it creates the site, installs ERPNext, enables the scheduler and sets a generated Administrator password. After an image upgrade it runs the database migration once.

## Common Use Cases

- Running accounting, invoicing and tax for a small or mid-sized company
- Managing stock, warehouses, purchasing and sales orders in one system
- Tracking leads, opportunities and quotations alongside fulfilment and billing
- Manufacturing with bills of materials, work orders and production planning

## Dependencies for ERPNext Hosting

- ERPNext / Frappe (official `frappe/erpnext:v16.50.0` image, extended with supervisord)
- MariaDB 11.8
- Redis for cache
- Redis for job queues and realtime pub/sub

### Deployment Dependencies

- Frappe Docker (official container setup): https://github.com/frappe/frappe_docker
- ERPNext documentation: https://docs.frappe.io/erpnext
- Frappe framework documentation: https://docs.frappe.io/framework
- ERPNext releases: https://github.com/frappe/erpnext/releases

### Implementation Details

| Service | Image | Role |
|---|---|---|
| ERPNext | built from `services/erpnext` (`frappe/erpnext:v16.50.0` + supervisord) | nginx, Gunicorn, socket.io, short and long workers, scheduler; owns the `sites` volume |
| MariaDB | `mariadb:11.8.9` | Database (volume) |
| redis-cache | `redis:8.2` | Cache (no persistence) |
| redis-queue | `redis:8.2` | Job queues and realtime (volume) |

**First login:** wait for the first deploy to finish (site creation takes a few minutes), open the public URL and sign in as `Administrator` with the generated `ADMIN_PASSWORD` shown in the ERPNext service variables. Complete the setup wizard, then change the password and create your users.

**Scaling:** raise `WORKER_SHORT_PROCS`, `WORKER_LONG_PROCS`, `GUNICORN_WORKERS` or `GUNICORN_THREADS` and give the ERPNext service more memory. The service cannot run multiple replicas because it owns the `sites` volume. Raise `MARIADB_INNODB_BUFFER_POOL_SIZE` as your data grows.

**Versions:** the ERPNext version is the `ERPNEXT_VERSION` build argument in `services/erpnext/Dockerfile`. Change it within the v16 line and redeploy; the migration runs automatically once.

Frappe HR (payroll, leave, attendance) is a separate app and is not included in this image.

### Why Deploy ERPNext on Railway?

Railway provides the database, Redis services, persistent volumes and HTTPS domain in one project, so a complete ERPNext install comes up from a single template without server administration. You pay for the resources the ERP actually uses and can resize each service as your company grows.
