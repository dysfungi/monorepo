# ntfy

Self-hosted [ntfy][ntfy] push-notification server at
[ntfy.frank.sh](https://ntfy.frank.sh).

## Posture: public read-write, hardened

This instance is intentionally an **open relay** (`auth-default-access: read-write`),
mirroring ntfy.sh's own model where topic privacy is by obscurity of the topic name.
Requiring auth would add little privacy here — the host is discoverable via TLS
certificate-transparency logs and leaks in push payloads — so instead the instance is
**hardened** to bound abuse:

- **Attachments disabled** — no `attachment-cache-dir`, so nobody can park files on the PVC.
- **Per-visitor rate limits** — request burst/replenish + a daily message cap.
- **Short cache TTL** (`cache-duration: 12h`).
- **`behind-proxy: true`** — rate limits key off the real client IP via the NGF gateway.

## Storage

SQLite message cache on a 2Gi Vultr block-storage PVC mounted at `/var/cache/ntfy`
(survives pod restarts). The chart runs a single replica with a `Recreate` strategy,
so the `ReadWriteOnce` volume always has a single writer.

## Ingress

Exposed through the shared [`gateway-route`](../../modules/gateway-route) module, which
attaches an `HTTPRoute` to the `prod-web` Gateway's `https-wildcard.frank.sh` listener
(TLS served by the existing `*.frank.sh` wildcard certificate — nothing to provision).
The module's `upstream_read_timeout` knob emits a `SnippetsFilter` raising nginx's
`proxy_read_timeout` so long-lived subscription streams are not severed.

## Going private later

Low-regret, no data migration:

1. In [`helm.tf`](./helm.tf), set `ntfy.authDefaultAccess = "deny-all"`.
2. Uncomment the `auth-users` / `auth-access` block in `ntfy.extraConfig` and supply a
   bcrypt hash (`ntfy user hash`) via the External Secrets Operator — mirror
   `terraform/applications/miniflux/external_secret_miniflux.{tf,yaml}` — injected as an
   env var the config references. The `auth-file` SQLite DB lands on the **same** PVC, so
   no storage change is needed.

See the [ntfy access-control docs](https://docs.ntfy.sh/config/#access-control).

<!--- REFERENCE LINKS --->

[ntfy]: https://ntfy.sh/
