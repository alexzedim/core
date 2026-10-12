#!/usr/bin/env node
/**
 * Patch caddy-proxy-manager (pinned tag) to add the Selectel DNS
 * provider (github.com/caddy-dns/selectel):
 *   1. docker/caddy/go.mod   — pinned module require
 *   2. docker/caddy/build.sh — xcaddy --with entry
 *   3. src/lib/dns-providers.ts — panel provider registry entry
 *   4. docker/caddy/Dockerfile — builder GOPROXY (see the patch below)
 *
 * Run from the upstream repo root:  node apply-selectel.cjs v1.13.3
 * Idempotent: skips parts that are already applied. CommonJS — the
 * self-hosted runner ships an old Node without ESM.
 */
"use strict";
var fs = require("fs");

var tag = process.argv[2] || "v1.13.3";
var SEL_VERSION = "v1.2.0";

function patch(file, from, to) {
  var text = fs.readFileSync(file, "utf8");
  if (text.indexOf(to) !== -1) {
    console.log("= " + file + ": already patched");
    return;
  }
  if (text.indexOf(from) === -1) {
    throw new Error(file + ": anchor not found — upstream layout changed, patch manually");
  }
  fs.writeFileSync(file, text.replace(from, to));
  console.log("+ " + file + ": patched");
}

// 1. go.mod — add the module next to the other caddy-dns requires
patch(
  "docker/caddy/go.mod",
  "github.com/caddy-dns/rfc2136 v1.0.0\n",
  "github.com/caddy-dns/rfc2136 v1.0.0\n\tgithub.com/caddy-dns/selectel " + SEL_VERSION + "\n"
);

// 2. build.sh — add to the MODULES heredoc
patch(
  "docker/caddy/build.sh",
  "github.com/caddy-dns/rfc2136\n",
  "github.com/caddy-dns/rfc2136\ngithub.com/caddy-dns/selectel\n"
);

// 3. dns-providers.ts — registry entry before the BASE_DNS_PROVIDERS close
var entry = [
  "  {",
  '    name: "selectel",',
  '    displayName: "Selectel",',
  '    description: "Selectel DNS API (keystone user/password; the zone must live on Selectel DNS)",',
  '    docsUrl: "https://github.com/caddy-dns/selectel",',
  '    modulePath: "github.com/caddy-dns/selectel",',
  "    fields: [",
  '      { key: "user", label: "User", type: "string", required: true, placeholder: "cert-sync" },',
  '      { key: "password", label: "Password", type: "password", required: true },',
  '      { key: "account_id", label: "Account ID", type: "string", required: true, placeholder: "454323" },',
  '      { key: "project_name", label: "Project Name", type: "string", required: true, placeholder: "cmnw" },',
  "    ],",
  "  },",
  "",
].join("\n");
patch(
  "src/lib/dns-providers.ts",
  "];\n\n/**\n * Full provider registry.",
  entry + "];\n\n/**\n * Full provider registry."
);

// 4. Dockerfile — route the builder's Go module fetches away from
//    storage.googleapis.com: the runner's docker bridge is IPv4-only and
//    IPv4 egress to Google storage gets connection-reset (RU throttling),
//    while the host's IPv6 path is fine. goproxy.cn serves the module zips
//    and tunnels checksum-db (sum.golang.org) verification through itself;
//    direct→github.com covers anything the mirror lacks.
patch(
  "docker/caddy/Dockerfile",
  "RUN sh ./update-compatibility-pins.sh",
  "ENV GOPROXY=https://goproxy.cn,direct\nRUN sh ./update-compatibility-pins.sh"
);

// 5. caddy.ts — L4 TLS termination for Postgres: when an L4 proxy host opts
//    in via meta {"postgresSsl": true}, emit caddy-l4's postgres_tls handler
//    BEFORE the tls handler, with an ALPN connection policy advertising the
//    "postgresql" protocol. postgres_tls only consumes the PostgreSQL
//    SSLRequest preamble and replies 'S' (per its docs, "put a tls handler
//    next to perform the actual TLS handshake"); the plain "tls" handler
//    alone expects the ClientHello as the first bytes, which breaks every
//    standard libpq/JDBC client, and without the ALPN policy libpq 17+
//    clients die with "tlsv1 alert no application protocol". Matched routes
//    for such hosts must use matcherType "none" — the tls_sni matcher peeks
//    a ClientHello that never comes (SSLRequest arrives first).
patch(
  "src/lib/caddy.ts",
  '      if (host.tlsTermination) {\n        handlers.push({ handler: "tls" });\n      }',
  '      if (host.tlsTermination) {\n        if ((meta as unknown as { postgresSsl?: boolean } | null)?.postgresSsl) {\n          handlers.push({ handler: "postgres_tls" }, { handler: "tls", connection_policies: [{ alpn: ["postgresql"] }] });\n        } else {\n          handlers.push({ handler: "tls" });\n        }\n      }'
);

console.log("selectel patch applied against " + tag);
