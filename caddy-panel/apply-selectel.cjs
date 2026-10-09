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

console.log("selectel patch applied against " + tag);
