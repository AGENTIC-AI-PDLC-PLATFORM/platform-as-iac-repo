#!/usr/bin/env python3
"""Zone token broker of the platform-as-iac-repo runners (ADR control C1).

Runs as root on every ephemeral runner VM and listens on 127.0.0.1 only. A job sends its GitHub
Actions OIDC token and asks for "plan" or "apply". If the token passes the checks for that role,
the broker returns a one-hour access token for this zone's plan or apply service account, minted
with the VM's own identity. Jobs cannot reach that identity themselves (the startup script blocks
the metadata server for the runner user), so a zone's credentials exist only on that zone's
runners, and every decision is written to Cloud Logging with the job that asked.

    plan   any job of the repository, on a self-hosted runner
    apply  the apply workflow, on refs/heads/main, in the zone's protected GitHub environment

Configuration: /etc/platform-as-iac-repo/broker.json (written from the instance template's metadata).
"""
import json
import logging
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt  # Debian package python3-jwt (PyJWT); RS256 needs python3-cryptography

CONFIG_PATH = os.environ.get("BROKER_CONFIG", "/etc/platform-as-iac-repo/broker.json")
GITHUB_ISSUER = "https://token.actions.githubusercontent.com"
METADATA_TOKEN_URL = (
    "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token"
)
GENERATE_TOKEN_URL = (
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/{}:generateAccessToken"
)
LOGGING_URL = "https://logging.googleapis.com/v2/entries:write"
MAX_REQUEST_BYTES = 16384
REQUIRED_CONFIG = ("zone", "project_id", "repository", "audience", "apply_workflow", "service_accounts")


class Denied(Exception):
    """The token does not entitle the job to the requested credentials."""


def load_config(path=CONFIG_PATH):
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    missing = [key for key in REQUIRED_CONFIG if key not in cfg]
    if missing:
        raise ValueError(f"broker config is missing {', '.join(missing)}")
    return cfg


def verify(token, cfg, jwks_client):
    """Return the claims of a valid GitHub Actions OIDC token for this broker, or raise Denied."""
    try:
        key = jwks_client.get_signing_key_from_jwt(token).key
        return jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=cfg["audience"],
            issuer=cfg.get("issuer", GITHUB_ISSUER),
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
            leeway=30,
        )
    except jwt.PyJWTError as e:
        raise Denied(f"invalid token: {e}") from e


def authorize(claims, role, cfg):
    """Raise Denied unless these claims may receive this role's credentials."""
    if role not in ("plan", "apply"):
        raise Denied(f"unknown role {role!r}")
    if claims.get("repository") != cfg["repository"]:
        raise Denied(f"token is not from {cfg['repository']}")
    if claims.get("runner_environment") != "self-hosted":
        raise Denied("token is not from a self-hosted runner")
    if role == "apply":
        if claims.get("ref") != "refs/heads/main":
            raise Denied("apply needs a job on refs/heads/main")
        if claims.get("environment") != cfg["zone"]:
            raise Denied(f"apply needs the protected environment {cfg['zone']!r}")
        if claims.get("job_workflow_ref") != f"{cfg['apply_workflow']}@refs/heads/main":
            raise Denied("apply needs the apply workflow from main")


def _post_json(url, body, token):
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def vm_token():
    request = urllib.request.Request(METADATA_TOKEN_URL, headers={"Metadata-Flavor": "Google"})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)["access_token"]


def mint(service_account):
    """One-hour access token for service_account, impersonated with the VM's identity."""
    body = {"scope": ["https://www.googleapis.com/auth/cloud-platform"], "lifetime": "3600s"}
    out = _post_json(GENERATE_TOKEN_URL.format(service_account), body, vm_token())
    return out["accessToken"], out["expireTime"]


def audit(cfg, entry):
    """Record the decision in the journal and, best effort, in Cloud Logging."""
    logging.info(json.dumps(entry, sort_keys=True))
    body = {
        "logName": f"projects/{cfg['project_id']}/logs/platform-as-iac-repo-broker",
        "resource": {"type": "global", "labels": {"project_id": cfg["project_id"]}},
        "entries": [{"severity": "NOTICE" if entry["granted"] else "WARNING", "jsonPayload": entry}],
    }
    try:
        _post_json(LOGGING_URL, body, vm_token())
    except (urllib.error.URLError, OSError, ValueError) as e:
        logging.warning("could not write the decision to Cloud Logging: %s", e)


def decision(cfg, role, claims, granted, reason=""):
    keys = ("repository", "ref", "environment", "event_name", "run_id", "run_attempt",
            "actor", "sha", "workflow", "job_workflow_ref", "runner_environment")
    entry = {key: claims.get(key) for key in keys}
    entry.update({"zone": cfg["zone"], "role": role, "granted": granted, "reason": reason})
    return entry


class Handler(BaseHTTPRequestHandler):
    server_version = "platform-as-iac-repo-broker"

    def do_POST(self):  # noqa: N802 (http.server API)
        cfg = self.server.cfg
        if self.path != "/token":
            self.reply(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_REQUEST_BYTES:
                raise ValueError("bad length")
            request = json.loads(self.rfile.read(length))
            role, token = request["role"], request["token"]
        except (ValueError, KeyError, TypeError):
            self.reply(400, {"error": "expected JSON {\"role\": \"plan|apply\", \"token\": \"<OIDC token>\"}"})
            return

        claims = {}
        try:
            claims = verify(token, cfg, self.server.jwks)
            authorize(claims, role, cfg)
        except Denied as e:
            audit(cfg, decision(cfg, role, claims, False, str(e)))
            self.reply(403, {"error": str(e)})
            return

        service_account = cfg["service_accounts"][role]
        try:
            access_token, expire_time = mint(service_account)
        except (urllib.error.URLError, OSError, KeyError, ValueError) as e:
            audit(cfg, decision(cfg, role, claims, False, f"minting failed: {e}"))
            self.reply(502, {"error": f"could not mint the {role} token"})
            return

        audit(cfg, decision(cfg, role, claims, True))
        self.reply(200, {"access_token": access_token, "expire_time": expire_time,
                         "service_account": service_account})

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):  # noqa: A002 (http.server API); decisions go to audit()
        pass


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    cfg = load_config()
    server = ThreadingHTTPServer(("127.0.0.1", int(cfg.get("port", 8099))), Handler)
    server.cfg = cfg
    server.jwks = jwt.PyJWKClient(cfg.get("jwks_url", f"{GITHUB_ISSUER}/.well-known/jwks"))
    logging.info("token broker for zone %s listening on 127.0.0.1:%s", cfg["zone"], cfg.get("port", 8099))
    server.serve_forever()


if __name__ == "__main__":
    main()
