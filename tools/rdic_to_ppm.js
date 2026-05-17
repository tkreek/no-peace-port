#!/usr/bin/env node

const fs = require("fs");

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  console.error("Usage: node tools/rdic_to_ppm.js <input.pic> <output.ppm>");
  process.exit(1);
}

const input = fs.readFileSync(inputPath);
if (input.subarray(0, 4).toString("ascii") !== "RDIC") {
  throw new Error(`${inputPath} is not an RDIC image`);
}

const width = input.readUInt32LE(4);
const height = input.readUInt32LE(8);
const paletteTag = input.subarray(16, 20).toString("ascii");
if (paletteTag !== "COLS") {
  throw new Error(`Unsupported RDIC palette tag: ${paletteTag}`);
}

const paletteOffset = 20;
const pixelTagOffset = paletteOffset + 256 * 3;
const pixelTag = input.subarray(pixelTagOffset, pixelTagOffset + 4).toString("ascii");
if (pixelTag !== "PRAW") {
  throw new Error(`Unsupported RDIC pixel tag: ${pixelTag}`);
}

const pixelOffset = pixelTagOffset + 4;
const pixelCount = width * height;
const header = `P6\n${width} ${height}\n255\n`;
const output = Buffer.alloc(Buffer.byteLength(header) + pixelCount * 3);
let writeOffset = output.write(header, 0, "ascii");

for (let index = 0; index < pixelCount; index += 1) {
  const colorIndex = input[pixelOffset + index] * 3 + paletteOffset;
  output[writeOffset++] = input[colorIndex];
  output[writeOffset++] = input[colorIndex + 1];
  output[writeOffset++] = input[colorIndex + 2];
}

fs.writeFileSync(outputPath, output);
console.log(`${width}x${height} indexed pixel_offset=${pixelOffset}`);
