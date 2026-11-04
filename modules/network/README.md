# modules/network

Private network for one zone (or one runner pool), with egress-deny by default.

| What | How | Control |
|---|---|---|
| No route to the internet | VPC created with `delete_default_routes_on_create = true`; no Cloud NAT, no external IPs | C5 |
| Google APIs without internet | Route to `private.googleapis.com` (199.36.153.8/30) and private DNS for `googleapis.com` and `pkg.dev` | C5 allows this route only |
| Egress only through the company DLP reverse proxy | Private Service Connect endpoint to the proxy's service attachment, used as an explicit proxy (`dlp_proxy_url` output) | C5 |
| Private connectivity to the control plane | Private Service Connect endpoints to the control plane's published services; one-way, so they create no path between zones | C3 |
| Firewall | Egress denied except to Google APIs and to the network's own subnets; no ingress from outside the network | C3, C5 |

Used by `bootstrap/` (one runner network per project) and by every zone root, always through a
release tag: `git::https://github.com/platform-team/platform-as-iac-repo.git//modules/network?ref=network-vX.Y.Z` (C9).
