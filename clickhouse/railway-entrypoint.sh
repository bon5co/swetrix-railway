#!/bin/bash
# Railway-specific preparation, then hand over to the stock ClickHouse entrypoint.
set -eo pipefail

DATA_DIR="${CLICKHOUSE_DATA_DIR:-/var/lib/clickhouse}"

# Railway mounts volumes owned by uid 0 and ext4 puts a lost+found in them.
# ClickHouse scans the data directory for databases and lost+found is not one.
if [ -d "$DATA_DIR" ]; then
  rm -rf "$DATA_DIR/lost+found" || true
  if [ "$(id -u)" = "0" ]; then
    chown -R clickhouse:clickhouse "$DATA_DIR" || true
  fi
fi

# Size the query thread limit to THIS container.
#
# The upstream self-hosting compose pins concurrent_threads_soft_limit_num to 1
# so ClickHouse survives a 1 GB VPS. On Railway the container has several vCPU
# and that setting serialises every dashboard query onto one of them. Read the
# cgroup quota and let ClickHouse use what the container actually has.
#
# Memory is deliberately NOT set here: ClickHouse 25.8 reads the cgroup limit
# itself (measured 2026-08-02 — in a container capped at 2 GiB it reported
# CGroupMemoryTotal 2.00 GiB and max_server_memory_usage 1932735283 = 0.9 x
# 2 GiB, while OSMemoryTotal still showed the host's 23.88 GiB). Overriding it
# would only lower the ceiling.
cpu_max_file=/sys/fs/cgroup/cpu.max

cpus=""
if [ -r "$cpu_max_file" ]; then
  read -r quota period < "$cpu_max_file" || true
  if [ "$quota" != "max" ] && [ -n "$quota" ] && [ -n "$period" ] && [ "$period" -gt 0 ]; then
    cpus=$(( quota / period ))
    [ "$cpus" -lt 1 ] && cpus=1
  fi
fi
[ -z "$cpus" ] && cpus=$(nproc 2>/dev/null || echo 2)

{
  echo '<clickhouse>'
  echo "  <concurrent_threads_soft_limit_num>${cpus}</concurrent_threads_soft_limit_num>"
  echo '</clickhouse>'
} > /etc/clickhouse-server/config.d/railway-limits.xml

echo "[swetrix-clickhouse] cgroup cpus=${cpus} -> concurrent_threads_soft_limit_num=${cpus}"

exec /entrypoint.sh "$@"
