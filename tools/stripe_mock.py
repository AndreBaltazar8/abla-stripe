#!/usr/bin/env python3
import http.server
import json
import socketserver
import sys


class StripeFixtureHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    requests_seen = 0

    def log_message(self, format, *args):
        return

    def respond(self, status, body, headers):
        encoded = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Connection", "close")
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(encoded)

    def do_POST(self):
        StripeFixtureHandler.requests_seen += 1
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode()
        expected = (
            "email=andr%C3%A9%40example.com&"
            "metadata%5Baccount_id%5D=acc_123"
        )
        checks = {
            "path": self.path == "/v1/customers",
            "body": body == expected,
            "authorization": self.headers.get("Authorization") == "Bearer sk_test_protocol_fixture",
            "api_version": self.headers.get("Stripe-Version") == "2026-07-29.dahlia",
            "idempotency": self.headers.get("Idempotency-Key") == "fixture-customer-1",
            "user_agent": self.headers.get("User-Agent") == "abla-stripe/0.1.0",
            "client_information": json.loads(self.headers.get("X-Stripe-Client-User-Agent", "{}")) == {
                "lang": "abla",
                "publisher": "community",
                "bindings_version": "0.1.0",
                "lang_version": "0.1",
                "application": {
                    "name": "integration-test",
                    "version": "0.1.0",
                    "url": "https://example.test",
                },
            },
            "application": self.headers.get("X-Abla-Stripe-App") == "integration-test/0.1.0",
        }
        if not all(checks.values()):
            print(
                "Stripe fixture mismatch: " +
                ", ".join(name for name, passed in checks.items() if not passed),
                file=sys.stderr,
                flush=True,
            )
            self.respond(400, {"error": {"type": "invalid_request_error", "message": "fixture mismatch"}}, {"Request-Id": "req_fixture_mismatch"})
            return
        self.respond(200, {
            "id": "cus_fixture",
            "object": "customer",
            "email": "andré@example.com",
            "name": "André",
            "livemode": False,
            "metadata": {"account_id": "acc_123"},
        }, {
            "Request-Id": "req_fixture_customer",
            "Stripe-Version": "2026-07-29.dahlia",
        })

    def do_GET(self):
        StripeFixtureHandler.requests_seen += 1
        if self.path != "/v1/fail":
            self.respond(404, {"error": {"type": "invalid_request_error", "message": "not found"}}, {"Request-Id": "req_fixture_not_found"})
            return
        self.respond(429, {
            "error": {
                "type": "invalid_request_error",
                "message": "Too many requests",
                "code": "rate_limit",
            }
        }, {
            "Request-Id": "req_fixture_failure",
            "Stripe-Rate-Limited-Reason": "global-rate",
            "Stripe-Should-Retry": "false",
        })


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


with ReusableTCPServer(("127.0.0.1", 0), StripeFixtureHandler) as server:
    print(server.server_address[1], flush=True)
    while StripeFixtureHandler.requests_seen < 2:
        server.handle_request()
