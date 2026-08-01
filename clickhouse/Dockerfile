# ClickHouse for Swetrix CE on Railway.
#
# Pinned to the same release Swetrix/selfhosting ships, with that repo's log and
# RAM configs baked in, plus the two things a Railway deploy needs and a plain
# compose port does not:
#
#   1. The data directory is a Railway volume, which is mounted root-owned and
#      carries a lost+found directory. ClickHouse refuses to treat lost+found as
#      a database and the server user cannot write the mount until it is chowned.
#   2. Thread and memory limits sized from the container's cgroup instead of the
#      1-thread setting upstream uses to survive a 1 GB VPS.
FROM clickhouse/clickhouse-server:25.8-alpine

# From Swetrix/selfhosting: drop the system log tables and the per-query logging
# that otherwise dominate disk use on a small analytics install.
COPY config/reduce-logs.xml /etc/clickhouse-server/config.d/reduce-logs.xml
COPY config/disable-user-logging.xml /etc/clickhouse-server/users.d/disable-user-logging.xml
COPY config/preserve-ram-config.xml /etc/clickhouse-server/config.d/preserve-ram-config.xml
COPY config/preserve-ram-user.xml /etc/clickhouse-server/users.d/preserve-ram-user.xml

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENV CLICKHOUSE_DB=analytics \
    CLICKHOUSE_USER=default

EXPOSE 8123

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
