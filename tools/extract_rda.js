#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const [inputPath, outputRoot] = process.argv.slice(2);

if (!inputPath || !outputRoot) {
  console.error("Usage: node tools/extract_rda.js <archive.rda> <output-dir>");
  process.exit(1);
}

const archive = fs.readFileSync(inputPath);
if (archive.subarray(0, 4).toString("ascii") !== "RDAR") {
  throw new Error(`${inputPath} is not an RDAR archive`);
}

const count = archive.readUInt32LE(8);
const names = [];
const starts = [];

names.push(readName(archive, 12, 124));

let tableOffset = 136;
for (let index = 1; index < count; index += 1, tableOffset += 128) {
  starts.push(archive.readUInt32LE(tableOffset));
  names.push(readName(archive, tableOffset + 4, 124));
}

starts.push(archive.readUInt32LE(tableOffset));

for (let index = 0; index < count; index += 1) {
  const start = starts[index];
  const end = index + 1 < count ? starts[index + 1] : archive.length;
  const relativePath = names[index].replace(/^\.\\/, "").replace(/\\/g, "/");
  const outputPath = path.join(outputRoot, relativePath);

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, archive.subarray(start, end));
  console.log(`${String(index).padStart(2, "0")} ${start.toString(16)} ${end - start} ${relativePath}`);
}

function readName(buffer, offset, length) {
  const raw = buffer.subarray(offset, offset + length);
  return raw.toString("latin1").split("\0")[0];
}
