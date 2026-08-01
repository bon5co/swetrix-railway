# Swetrix CE API for Railway.
#
# Same pinned upstream release as the web image, plus a boot guard: the API runs
# `clickhouse:initialise` before it starts, and that script exits 0 even when it
# cannot reach ClickHouse. On a fresh Railway project every service starts at
# once, so without the guard the API can come up against a ClickHouse that is
# still booting, create no tables, and then fail every request with
# UNKNOWN_TABLE until someone redeploys it.
FROM swetrix/swetrix-api:v5.3.1

USER root
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh
USER 999

# Baked so they never appear as blank required fields on the deploy form.
ENV CLICKHOUSE_PORT=8123 \
    CLICKHOUSE_USER=default \
    CLICKHOUSE_DATABASE=analytics \
    REDIS_PORT=6379 \
    REDIS_USER=default \
    CLIENT_IP_HEADER=x-forwarded-for \
    DISABLE_REGISTRATION=true \
    SMTP_MOCK=true \
    DEBUG_MODE=false \
    IS_PRIMARY_NODE=true

EXPOSE 5005

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD []
