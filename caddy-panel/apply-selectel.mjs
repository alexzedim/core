#!/usr/bin/env node
/**
 * Patch fuomag9/caddy-proxy-manager (pinned tag) to add the Selectel DNS
 * provider (github.com/caddy-dns/selectel):
 *   1. docker/caddy/go.mod   — pinned module require
 *   2. docker/caddy/build.sh — xcaddy --with entry
 *   3. src/lib/dns-providers.ts — panel provider registry entry
 *
 * Run from the upstream repo root:  node apply-selectel.mjs v1.13.3
 * Idempotent: skips parts that are already applied.
 */
import { readFileSync, writeFileSync } from "node:fs";

const tag = process.argv[2] || "v1.13.3";
const SEL_VERSION = "v1.2.0";

const patch = (file, from, to) => {
  let text = readFileSync(file, "utf8");
  if (text.includes(to)) {
    console.log(`= ${file}: already patched`);
    return;
  }
  if (!text.includes(from)) {
    throw new Error(`${file}: anchor not found — upstream layout changed, patch manually`);
  }
  text = text.replace(from, to);
  writeFileSync(file, text);
  console.log(`+ ${file}: patched`);
};

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
const entry = `  {
    name: "selectel",
    displayName: "Selectel",
    description: "Selectel DNS API (keystone user/password; the zone must live on Selectel DNS)",
    docsUrl: "https://github.com/caddy-dns/selectel",
    modulePath: "github.com/caddy-dns/selectel",
    fields: [
      { key: "user", label: "User", type: "string", required: true, placeholder: "cert-sync" },
      { key: "password", label: "Password", type: "password", required: true },
      { key: "account_id", label: "Account ID", type: "string", required: true, placeholder: "454323" },
      { key: "project_name", label: "Project Name", type: "string", required: true, placeholder: "cmnw" },
    ],
  },
`;
patch(
  "src/lib/dns-providers.ts",
  "];\n\n/**\n * Full provider registry.",
  entry + "];\n\n/**\n * Full provider registry."
);

console.log(`selectel patch applied against ${tag}`);
