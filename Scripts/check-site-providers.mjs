#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const providers = fs.readFileSync(path.join(root, "Sources/CodexBarCore/Providers/Providers.swift"), "utf8");
const providerEnum = providers.match(/public enum UsageProvider:[^{]+\{([\s\S]*?)\n\}/)?.[1];
assert(providerEnum, "UsageProvider enum not found");
const registered = [...providerEnum.matchAll(/^\s*case\s+(\w+)\s*$/gm)].map((match) => match[1]);
assert(registered.length > 0, "no registered providers found");

const site = fs.readFileSync(path.join(root, "docs/index.html"), "utf8");
const cards = [...site.matchAll(/<li data-provider="([^"]+)">([\s\S]*?)<\/li>/g)];
const listed = cards.map((match) => match[1]);
assert.deepEqual([...listed].sort(), [...registered].sort(), "site provider coverage differs from UsageProvider");

for (const [card, id, body] of cards) {
  const guide = body.match(/href="https:\/\/github\.com\/ColumbusLabs\/QuotaKit\/blob\/main\/(docs\/[^"#]+\.md)"/)?.[1];
  assert(guide, `${id} must link to a QuotaKit guide`);
  assert(!["docs/provider.md", "docs/providers.md"].includes(guide), `${id} needs its own guide`);
  assert(fs.existsSync(path.join(root, guide)), `${id} guide is missing: ${guide}`);
  const logo = body.match(/src="\.\/(logos\/[^"?]+)"/)?.[1];
  assert(logo, `${id} needs a logo`);
  for (const match of body.matchAll(/(?:src|data-dark-src)="\.\/(logos\/[^"?]+)"/g)) {
    assert(fs.existsSync(path.join(root, "docs", match[1])), `${id} logo is missing: ${match[1]}`);
  }
  assert(body.includes('class="name"'), `${id} needs a display name`);
  assert(body.includes('class="auth"'), `${id} needs an authentication label`);
  assert(!card.includes(" hidden"), `${id} must be visible`);
}

assert(site.includes(`${registered.length} providers, one menu bar`), "provider heading count is stale");
assert(site.includes(`across ${registered.length} providers`), "provider metadata count is stale");
console.log(`site provider catalog OK: ${registered.length} provider cards and guides`);
