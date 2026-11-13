"""Unit tests of the token broker's checks (run in CI: python3 -m unittest discover -s bootstrap/zone/files -p '*_test.py')."""
import json
import os
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

import broker
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

CFG = {
    "zone": "run",
    "project_id": "example-pdlc-run",
    "repository": "platform-team/platform-as-iac-repo",
    "audience": "platform-as-iac-repo-broker",
    "apply_workflow": "platform-team/platform-as-iac-repo/.github/workflows/apply.yml",
    "service_accounts": {"plan": "plan@example", "apply": "apply@example"},
}


class FakeJWKS:
    """Stands in for PyJWKClient: one known signing key."""

    def __init__(self, public_key):
        self.public_key = public_key

    def get_signing_key_from_jwt(self, token):
        jwt.get_unverified_header(token)  # raises like the real client on garbage
        return type("SigningKey", (), {"key": self.public_key})()


def new_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


GITHUB_KEY = new_key()
JWKS = FakeJWKS(GITHUB_KEY.public_key())


def token(key=GITHUB_KEY, **overrides):
    now = int(time.time())
    claims = {
        "iss": broker.GITHUB_ISSUER,
        "aud": "platform-as-iac-repo-broker",
        "sub": "repo:platform-team/platform-as-iac-repo:environment:run",
        "iat": now,
        "exp": now + 300,
        "repository": "platform-team/platform-as-iac-repo",
        "runner_environment": "self-hosted",
        "ref": "refs/heads/main",
        "environment": "run",
        "job_workflow_ref": "platform-team/platform-as-iac-repo/.github/workflows/apply.yml@refs/heads/main",
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, key, algorithm="RS256")


def check(role, tok):
    broker.authorize(broker.verify(tok, CFG, JWKS), role, CFG)


class BrokerChecks(unittest.TestCase):
    def test_apply_from_main_in_the_zone_environment_is_granted(self):
        check("apply", token())

    def test_plan_from_a_pull_request_is_granted(self):
        check("plan", token(ref="refs/pull/7/merge", environment=None,
                            job_workflow_ref="platform-team/platform-as-iac-repo/.github/workflows/pull-request.yml@refs/pull/7/merge"))

    def test_apply_from_a_pull_request_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "refs/heads/main"):
            check("apply", token(ref="refs/pull/7/merge"))

    def test_apply_in_another_zone_environment_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "protected environment"):
            check("apply", token(environment="build"))

    def test_apply_from_another_workflow_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "apply workflow"):
            check("apply", token(job_workflow_ref="platform-team/platform-as-iac-repo/.github/workflows/other.yml@refs/heads/main"))

    def test_another_repository_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "not from"):
            check("plan", token(repository="platform-team/other"))

    def test_github_hosted_runner_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "self-hosted"):
            check("plan", token(runner_environment="github-hosted"))

    def test_wrong_audience_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "invalid token"):
            check("plan", token(aud="https://github.com/platform-team"))

    def test_expired_token_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "invalid token"):
            check("plan", token(iat=int(time.time()) - 900, exp=int(time.time()) - 600))

    def test_token_signed_by_another_key_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "invalid token"):
            check("apply", token(key=new_key()))

    def test_garbage_is_denied(self):
        with self.assertRaises(broker.Denied):
            check("plan", "not-a-jwt")

    def test_unknown_role_is_denied(self):
        with self.assertRaisesRegex(broker.Denied, "unknown role"):
            check("owner", token())


class BrokerHTTP(unittest.TestCase):
    """The HTTP surface: status codes, and no token minted unless the checks pass."""

    def setUp(self):
        self.json, self.request = json, urllib.request
        self.minted: list[str] = []
        self.audited: list[dict] = []
        self.saved = broker.mint, broker.audit

        def fake_mint(service_account):
            self.minted.append(service_account)
            return "ya29.test-token", "2026-11-03T18:00:00Z"

        broker.mint = fake_mint
        broker.audit = lambda cfg, entry: self.audited.append(entry)
        self.server = broker.BrokerServer(("127.0.0.1", 0), CFG, JWKS)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        broker.mint, broker.audit = self.saved

    def post(self, path, body):
        data = body if isinstance(body, bytes) else self.json.dumps(body).encode()
        req = self.request.Request(self.url + path, data=data, method="POST",
                                   headers={"Content-Type": "application/json"})
        opener = self.request.build_opener(self.request.ProxyHandler({}))
        try:
            with opener.open(req, timeout=10) as resp:
                return resp.status, self.json.load(resp)
        except self.request.HTTPError as e:
            return e.code, self.json.load(e)

    def test_plan_token_is_returned_and_audited(self):
        status, body = self.post("/token", {"role": "plan", "token": token(ref="refs/pull/7/merge")})
        self.assertEqual(status, 200)
        self.assertEqual(body["service_account"], "plan@example")
        self.assertEqual(self.minted, ["plan@example"])
        self.assertTrue(self.audited[-1]["granted"])

    def test_apply_for_a_pull_request_is_refused_without_minting(self):
        status, body = self.post("/token", {"role": "apply", "token": token(ref="refs/pull/7/merge")})
        self.assertEqual(status, 403)
        self.assertIn("refs/heads/main", body["error"])
        self.assertEqual(self.minted, [])
        self.assertFalse(self.audited[-1]["granted"])

    def test_malformed_request_is_rejected(self):
        status, _ = self.post("/token", b"not json")
        self.assertEqual(status, 400)
        self.assertEqual(self.minted, [])

    def test_unknown_path_is_404(self):
        status, _ = self.post("/other", {"role": "plan", "token": token()})
        self.assertEqual(status, 404)


class BrokerOutbound(unittest.TestCase):
    """The broker's own requests (bandit B310): http and https only, sent as urlopen sent them."""

    def setUp(self):
        self.seen: list[dict] = []
        seen = self.seen

        class Upstream(BaseHTTPRequestHandler):
            """Stands in for the metadata server (GET) and IAM Credentials (POST)."""

            def do_GET(self):  # noqa: N802 (http.server API)
                self.answer({"access_token": "vm-token"})

            def do_POST(self):  # noqa: N802 (http.server API)
                self.answer({"accessToken": "ya29.minted", "expireTime": "2026-11-03T18:00:00Z"})

            def answer(self, body):
                length = int(self.headers.get("Content-Length", "0"))
                seen.append({"method": self.command, "path": self.path,
                             "flavor": self.headers.get("Metadata-Flavor"),
                             "authorization": self.headers.get("Authorization"),
                             "body": self.rfile.read(length)})
                data = json.dumps(body).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, format, *args):  # noqa: A002 (http.server API)
                pass

        upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        threading.Thread(target=upstream.serve_forever, daemon=True).start()
        self.addCleanup(upstream.server_close)
        self.addCleanup(upstream.shutdown)
        url = f"http://127.0.0.1:{upstream.server_address[1]}"
        # Reach the local server directly, as the runner reaches Google's APIs (no_proxy).
        for patch in (
            mock.patch.dict(os.environ, {"no_proxy": "127.0.0.1", "NO_PROXY": "127.0.0.1"}),
            mock.patch.object(broker, "METADATA_TOKEN_URL", f"{url}/metadata/token"),
            mock.patch.object(broker, "GENERATE_TOKEN_URL", f"{url}/iam/{{}}:generateAccessToken"),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def test_mint_asks_the_metadata_server_then_iam_credentials(self):
        self.assertEqual(broker.mint("apply@example"), ("ya29.minted", "2026-11-03T18:00:00Z"))
        get, post = self.seen
        self.assertEqual((get["method"], get["path"], get["flavor"]),
                         ("GET", "/metadata/token", "Google"))
        self.assertEqual((post["method"], post["path"], post["authorization"]),
                         ("POST", "/iam/apply@example:generateAccessToken", "Bearer vm-token"))
        self.assertEqual(json.loads(post["body"])["lifetime"], "3600s")

    def test_other_schemes_are_refused(self):
        for url in ("file:///etc/hostname", "data:,x"):
            with self.subTest(url=url), self.assertRaisesRegex(urllib.error.URLError, "unknown url type"):
                broker.OPENER.open(url, timeout=1)


if __name__ == "__main__":
    unittest.main()
