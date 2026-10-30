# swetrix-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/swetrix-ce-v531-or-google-analytics-alte?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [Swetrix CE template](https://railway.com/deploy/swetrix-ce-v531-or-google-analytics-alte?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

Railway-tuned images for [Swetrix Community Edition](https://github.com/Swetrix/swetrix) v5.3.1 —
the privacy-first, cookieless Google Analytics alternative.

Three images, published to GHCR on every push to `main`:

| Image | What it is |
|---|---|
| `ghcr.io/bon5co/swetrix-railway` | Web UI + same-origin nginx gateway in one container |
| `ghcr.io/bon5co/swetrix-railway-api` | Swetrix API with a ClickHouse readiness guard |
| `ghcr.io/bon5co/swetrix-railway-clickhouse` | ClickHouse 25.8 with Swetrix's log/RAM configs, volume-safe, threads sized to the container |

Everything below was measured on 2026-08-02 against the stack running locally, not inferred.

## Why these wrappers exist

### 1. ClickHouse holds the whole instance, so it needs a volume

Swetrix CE has no second database. `migrations/clickhouse/initialise_selfhosted.js` creates
`user`, `project`, `refresh_token`, `salt`, `funnel`, `session_replay_chunks` and the event tables
in ClickHouse, and `apps/community/src/user/user.service.ts` reads accounts straight from it. A
ClickHouse service with no volume therefore loses the accounts, the projects and the analytics on
every redeploy — not just the traffic history.

Reproduced: register a user, recreate the ClickHouse container without a volume, and the next query
returns `Code: 60 ... UNKNOWN_TABLE`. With the volume mounted at `/var/lib/clickhouse`, the same
recreate returns the user.

### 2. `proxy_pass http://$variable/` silently drops the request path

The Swetrix UI hardcodes its API base to `${BASE_URL}/backend` in selfhosted mode
(`web/app/lib/constants/index.ts`), so the gateway has to strip that prefix. The natural-looking
way to write it is wrong: when `proxy_pass` names a **variable** upstream, nginx does not perform
its usual "replace the matched location prefix" rewrite — it replaces the entire request URI with
the literal URI given. Every `/backend/*` call then arrives at the API as `/`:

```
POST /backend/v1/auth/register  ->  {"message":"Cannot POST /","error":"Not Found","statusCode":404}
```

The gateway here strips the prefix with an explicit `rewrite ^/backend/(.*)$ /$1 break;` instead,
and registration/login return 201/200.

### 3. The upstream RAM configs are sized for a 1 GB VPS

`Swetrix/selfhosting` mounts `preserve-ram-config.xml`, which pins
`concurrent_threads_soft_limit_num` to `1`. That is the right call on a tiny box and a real handicap
on Railway, where the container has several vCPU. The entrypoint reads `/sys/fs/cgroup/cpu.max` and
sets the limit to the container's actual quota.

Measured in a 4-vCPU, 4 GB container, `SELECT count(), uniq(number % 100000) FROM
numbers_mt(1000000000) WHERE number % 7 = 0`, three runs each:

| Config | Runs | Median |
|---|---|---|
| upstream (`concurrent_threads_soft_limit_num=1`) | 3.963 / 3.894 / 3.858 s | **3.89 s** |
| cgroup-sized (`=4`) | 2.156 / 2.170 / 2.142 s | **2.16 s** |

Memory is deliberately left alone: ClickHouse 25.8 already reads the cgroup limit. In a container
capped at 2 GiB it reported `CGroupMemoryTotal 2.00 GiB` and `max_server_memory_usage 1932735283`
(0.9 × 2 GiB) while `OSMemoryTotal` still showed the host's 23.88 GiB. Overriding it would only
lower the ceiling.

### 4. One fewer always-on service

Upstream's compose runs the UI and nginx as separate containers. Railway bills per service, so
nginx runs beside the frontend it fronts: the deploy is UI+gateway, API, ClickHouse, Redis. If
either the frontend or nginx exits, the entrypoint takes the container down (`wait -n`) so Railway
restarts it, rather than leaving a gateway answering healthchecks in front of a dead UI.

### 5. The API can start before ClickHouse is listening

`npm run start:prod` runs `clickhouse:initialise` first, and that script exits 0 even when it cannot
reach ClickHouse — the API then serves requests with no tables until someone redeploys it. On
Railway every service in a new project starts at once, so the API entrypoint polls
`$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/ping` (90 × 5 s) before handing over.

## Registration

`DISABLE_REGISTRATION=true` is baked in. Swetrix allows the **first** account regardless
(`auth.service.ts` returns `false` from `isRegistrationDisabled()` while `usersCount === 0`), so the
deployer signs up as the owner and everyone after them is turned away with
`{"message":"Registration is disabled"}`. Set it to `false` to run an open instance.

## Local smoke test

```bash
docker network create swx
docker run -d --name swx-ch --network swx -v swx-chdata:/var/lib/clickhouse \
  -e CLICKHOUSE_PASSWORD=chpass ghcr.io/bon5co/swetrix-railway-clickhouse
docker run -d --name swx-redis --network swx redis:8.2.1 redis-server --requirepass redispass
docker run -d --name swx-api --network swx \
  -e CLICKHOUSE_HOST=http://swx-ch -e CLICKHOUSE_PASSWORD=chpass \
  -e REDIS_HOST=swx-redis -e REDIS_PASSWORD=redispass \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" -e BASE_URL=http://localhost:8099 \
  ghcr.io/bon5co/swetrix-railway-api
docker run -d --name swx-app --network swx -p 8099:8080 \
  -e API_UPSTREAM=swx-api:5005 -e BASE_URL=http://localhost:8099 ghcr.io/bon5co/swetrix-railway
```

`http://localhost:8099` redirects to `/login`; `curl http://localhost:8099/backend/ping` returns 200.

## Licence

The wrapper files here are MIT. Swetrix CE is licensed by its authors — see
[Swetrix/swetrix](https://github.com/Swetrix/swetrix).
