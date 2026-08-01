# Swetrix CE web UI + same-origin API gateway in one container.
#
# The Swetrix frontend hardcodes its API base to `${BASE_URL}/backend` in
# selfhosted mode (web/app/lib/constants/index.ts), so something must serve the
# UI and the API under one origin. Upstream's compose runs a separate nginx
# container to do it. Here nginx runs beside the frontend it fronts, which
# removes a whole always-on service and a hop from the deploy.
FROM swetrix/swetrix-fe:v5.3.1

USER root

# bash for `wait -n` (busybox ash does not have it): if either the frontend or
# nginx dies, the container must exit so Railway restarts it, rather than
# staying "healthy" while serving nothing.
RUN apk add --no-cache nginx bash

COPY nginx.conf.template /etc/nginx/railway.conf.template
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh \
    && mkdir -p /run/nginx /var/lib/nginx/tmp \
    && rm -f /etc/nginx/http.d/default.conf

# Baked so the deploy form stays empty: a literal-valued template variable
# publishes as required-with-no-default, an env default does not.
ENV NODE_ENV=production \
    __SELFHOSTED=true \
    PORT=8080 \
    FRONTEND_PORT=3000 \
    API_UPSTREAM=swetrix-api:5005

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD []
