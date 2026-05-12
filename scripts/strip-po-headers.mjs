#!/usr/bin/env node
// Strip churny metadata from .po files after `lingui extract`.
// Right now: drop POT-Creation-Date (changes every run, conflicts on every PR).
// Origins (`#: path:lineno`) are disabled in lingui.config.js itself.
import { readFileSync, writeFileSync } from "node:fs";
import { glob } from "node:fs/promises";

const CATALOG_GLOB = "packages/locale/locales/*/*.po";
const STRIP_PATTERN = /^"POT-Creation-Date: .*\\n"\n/m;

let touched = 0;
for await (const path of glob(CATALOG_GLOB)) {
  const src = readFileSync(path, "utf8");
  const out = src.replace(STRIP_PATTERN, "");
  if (out !== src) {
    writeFileSync(path, out);
    touched += 1;
  }
}
console.log(`strip-po-headers: ${touched} file(s) normalized`);
