#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import process from "node:process";

import { renderPublicationSQL } from "../src/publication-batch.mjs";

const usage = `Usage: node distribution/bin/render-publication-sql.mjs [publication.json|-]

Reads one publication JSON document and writes the three semicolon-separated D1
statements to stdout. Omit the argument, or pass -, to read JSON from stdin.`;

async function readStandardInput() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function main(argumentsList) {
  if (argumentsList.length === 1 && ["-h", "--help"].includes(argumentsList[0])) {
    process.stdout.write(`${usage}\n`);
    return;
  }

  if (argumentsList.length > 1) {
    throw new TypeError(usage);
  }

  const inputPath = argumentsList[0];
  const source = inputPath && inputPath !== "-"
    ? await readFile(inputPath, "utf8")
    : await readStandardInput();
  const publication = JSON.parse(source);
  process.stdout.write(renderPublicationSQL(publication));
}

try {
  await main(process.argv.slice(2));
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Unable to render publication SQL: ${message}\n`);
  process.exitCode = 1;
}
