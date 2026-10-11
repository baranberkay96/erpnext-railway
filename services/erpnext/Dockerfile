# ERPNext all-in-one service for Railway.
#
# Frappe expects every process (web, socket.io, workers, scheduler, nginx) to see
# the same `sites/` directory. Railway volumes attach to exactly one service, so
# this image runs all of them in one container under supervisord, on top of the
# official production image built by frappe/frappe_docker.
#
# Upgrade: change ERPNEXT_VERSION (same major line), redeploy. The entrypoint runs
# `bench --site all migrate` once when it sees a new version.
ARG ERPNEXT_VERSION=v16.50.0
FROM frappe/erpnext:${ERPNEXT_VERSION}

ARG ERPNEXT_VERSION
ENV ERPNEXT_IMAGE_VERSION=${ERPNEXT_VERSION}

USER root

# supervisord runs the Frappe processes; the official image has everything else
# (nginx, node, bench, wait-for-it, gettext-base).
RUN apt-get update \
    && apt-get install -y --no-install-recommends supervisor \
    && rm -rf /var/lib/apt/lists/* \
    # The site is served under a fixed name (SITE_NAME) so custom domains keep working.
    # socket.io checks that the Origin host equals the Host header, so the Origin must
    # follow the real request host instead of the site name.
    && sed -i 's|proxy_set_header Origin $proxy_x_forwarded_proto://${FRAPPE_SITE_NAME_HEADER};|proxy_set_header Origin $proxy_x_forwarded_proto://$host;|' \
        /templates/nginx/frappe.conf.template \
    && grep -q 'proxy_set_header Origin $proxy_x_forwarded_proto://$host;' /templates/nginx/frappe.conf.template \
    # The Railway volume hides the image's sites/ folder; keep bench's app metadata
    # (apps.json) so the bootstrap can restore it on every boot.
    && cp /home/frappe/frappe-bench/sites/apps.json /home/frappe/frappe-bench/.image-apps.json \
    # nginx: root master (can write to supervisord's stdout/stderr pipes), workers as frappe;
    # a fixed worker count instead of one per host CPU.
    && sed -i 's/^worker_processes auto;/user frappe root;\nworker_processes 2;/' /etc/nginx/nginx.conf \
    && grep -q '^user frappe root;' /etc/nginx/nginx.conf

COPY supervisord.conf.template /templates/supervisord.conf.template
COPY --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chmod=0755 railway-bootstrap.sh /usr/local/bin/railway-bootstrap.sh
COPY --chmod=0755 supervisor-fatal-exit.sh /usr/local/bin/supervisor-fatal-exit.sh

WORKDIR /home/frappe/frappe-bench

EXPOSE 8080

# Runs as root only to fix volume ownership, then drops to the `frappe` user.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
