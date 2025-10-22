# CMDBuild 4.1.0 · Authentik-Ready Docker Image

This repository contains a reproducible Docker build of **CMDBuild 4.1.0** pre‑patched to work with the Authentik identity provider (OIDC/OAuth2).  
It produces the image referenced in `docker-compose.yaml` and wraps the upstream `itmicus/cmdbuild:4.1.0` base image with:

- the **patched `OauthAuthenticator` classes** that read the Authentik discovery document (`.well-known/openid-configuration`) and use its endpoints instead of the stock Keycloak layout;
- an **entrypoint script** that prepares the database, bootstraps CMDBuild via the REST CLI and applies Authentik specific settings on first boot.

> 💡 **CMDBuild** is an open-source Enterprise CMDB and Asset Management platform built on Tomcat + PostgreSQL.  
> See [cmdbuild.org](https://www.cmdbuild.org/) for official documentation.

---

## Repository layout

```
├─ Dockerfile                 → Extends the base CMDBuild image, installs psql client, copies patches & entrypoint
├─ entrypoint/entrypoint.sh   → Initialization script executed by the container
├─ docker-compose.yaml        → Reference Compose configuration (PostgreSQL + CMDBuild containers)
├─ patches/oauth/*.class      → Patched Authentik-ready OAuth classes
└─ conf/, lib/…               → Optional extra Tomcat / CMDBuild configuration files
```

---

## Environment variables

The Compose file exports the variables below to the CMDBuild container; they can also be passed manually via `docker run`.

| Variable | Default / Example | Description |
| --- | --- | --- |
| `POSTGRES_HOST` | `cmdbuild_db` | Hostname of the PostgreSQL service |
| `POSTGRES_PORT` | `5432` | PostgreSQL port |
| `POSTGRES_DB` | `cmdbuild` | Database name created via entrypoint |
| `POSTGRES_USER` | `postgres` | Admin role used for bootstrap (`dbconfig drop/create`) |
| `POSTGRES_PASSWORD` | `postgres` | Password for the admin role |
| `CMDBUILD_DUMP` | `demo.dump.xz` | Demo data file restored by the base image (optional) |
| `JAVA_OPTS` | `-Xmx6000m -Xms3000m` | JVM tuning for Tomcat |
| `CMDBUILD_DNS` | `cmdbuild.example.com` | Optional hostname used to configure Tomcat as HTTPS reverse proxy |
| `AUTHENTIK_SERVICE_URI` | `https://dns/application/o/cmdbuild` | Authentik application base URL used to fetch discovery metadata |
| `AUTHENTIK_OAUTH_PROTOCOL` | `OP_CUSTOM` (🔥 recommended) | CMDBuild protocol enum. Must be `OP_CUSTOM` for Authentik |
| `AUTHENTIK_CMDBUILD_REDIRECT_URL` | `http://ip:8080/cmdbuild` | Redirect URI registered in Authentik |
| `AUTHENTIK_CMDBUILD_CLIENT_ID` | `cmdbuild` | OIDC client identifier |
| `AUTHENTIK_CMDBUILD_CLIENT_SECRET` | _secret_ | OIDC client secret |
| `CMDBUILD_AUTH_MODULES` | `default,oauth` | Active login modules |
| `AUTHENTIK_CMBDUILD_OPENID_SCOPE` | `openid profile email` | Scopes requested during login |
| `AUTHENTIK_CMBDUILD_OPENID_LOGIN_TYPE` | `username` | CMDBuild login type (`email`, `username`, `auto`, …) |
| `AUTHENTIK_CMBDUILD_OPENID_LOGIN_ATTRIBUTE` | `preferred_username` | Attribute taken from the ID token/UserInfo to map CMDBuild users |
| `AUTHENTIK_CMBDUILD_OPENID_LOGIN_DESCRIPTION` | `Authentik` | Friendly name shown in the login widget |
| `AUTHENTIK_CMBDUILD_OPENID_PROTOCOL` | `openidconnect` | CMDBuild login module protocol label |
| `AUTHENTIK_CMBDUILD_OPENID_LOGOUT_ENABLED` | `true` | Whether Single Logout is enabled |

> ⚠️ If `AUTHENTIK_OAUTH_PROTOCOL` is not set to `OP_CUSTOM`, CMDBuild falls back to the legacy Keycloak endpoints and Authentik will reply with **404 Not Found**.

---

## Entry point behaviour (`entrypoint/entrypoint.sh`)

On container start the script:

1. Regenerates `conf/cmdbuild/database.conf` with the database credentials taken from env variables.
2. If it is the first boot (flag file absent):
   - If `CMDBUILD_DNS` is set, rewrites Tomcat’s `server.xml` connector so that the instance works correctly behind an HTTPS reverse proxy.
   - Runs `cmdbuild.sh dbconfig drop` and `cmdbuild.sh dbconfig create empty` to ensure a clean schema.
   - Launches Tomcat in background, polls the UI and REST endpoints until they become reachable.
   - Uses `cmdbuild.sh restws setconfig` to push all Authentik-related settings (client, secret, scope, etc.).
   - Marks the initialization as done.
3. Restarts Tomcat in foreground so the container stays up.

Subsequent restarts skip the bootstrap steps and simply start Tomcat.

---

## How to build & run

### 1. Build the image

```bash
docker compose build --no-cache cmdbuild_app
# or standalone:
docker build --no-cache -t cmdbuild:patched .
```

### 2. Launch the stack

```bash
docker compose up -d
```

The PostgreSQL service (`cmdbuild_db`) starts first; once it is healthy the CMDBuild container runs the initialization and remains available on port **8080** (mapped to the host).

### 3. Monitor logs

```bash
docker compose logs -f cmdbuild_app
```

Relevant messages you should see on the first boot:

- `Ricreo database (drop + create empty)...`
- `UI pronta, verifico disponibilità backend...`
- `Configuro integrazione Authentik...`
- `oauth combined user info map:` entries when a user performs the first login.

---

## User provisioning & default access

- CMDBuild still stores user entries locally. **Create the users first** (Administration → Users) leaving the password field empty; the Authentik login will supply the identity but CMDBuild needs the record to exist.
- Final configurations (groups, permissions, etc.) can be done with the default admin credentials: `admin / admin` on `http://<host>:8080/cmdbuild`.
- After the Authentik login succeeds, CMDBuild maps the user based on the attribute configured in `AUTHENTIK_CMBDUILD_OPENID_LOGIN_ATTRIBUTE` (e.g. `preferred_username`, `email`).

---

## First login flow

1. Open `http://<host>:8080/cmdbuild`.
2. Click “Login with Authentik”.
3. You should now be redirected to Authentik’s `/authorize/` endpoint (no more `/auth` 404).
4. After authentication, CMDBuild maps the user according to the configured attribute (`preferred_username`, `email`, …).

Enjoy your Authentik-enabled CMDBuild environment! 🚀

---

## Reverse proxy support

- Set `CMDBUILD_DNS` to the public hostname exposed by your HTTPS reverse proxy (for example `cmdbuild.example.com`).
- On the first boot the entrypoint rewrites Tomcat’s `server.xml` connector so that `proxyName`, `proxyPort=443` and `scheme=https` are in place, preventing mixed-content issues and making CMDBuild generate correct URLs behind the proxy.
- Leave `CMDBUILD_DNS` unset to keep the stock HTTP connector (default port 8080, no proxy headers).
