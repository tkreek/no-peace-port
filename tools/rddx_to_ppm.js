#!/usr/bin/env node

const fs = require("fs");

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  console.error("Usage: node tools/rddx_to_ppm.js <input.spr> <output.ppm>");
  process.exit(1);
}

const input = fs.readFileSync(inputPath);
if (input.subarray(0, 4).toString("ascii") !== "RDDX") {
  throw new Error(`${inputPath} is not an RDDX image`);
}

const width = input.readUInt32LE(4);
const height = input.readUInt32LE(8);
const format = input.subarray(16, 20).toString("ascii");
if (format !== "P16B") {
  throw new Error(`Unsupported RDDX pixel format: ${format}`);
}

const pixelBytes = width * height * 2;
const pixelOffset = input.length - pixelBytes;
const output = Buffer.alloc(Buffer.byteLength(`P6\n${width} ${height}\n255\n`) + width * height * 3);
let writeOffset = output.write(`P6\n${width} ${height}\n255\n`, 0, "ascii");

for (let readOffset = pixelOffset; readOffset < input.length; readOffset += 2) {
  const value = input.readUInt16LE(readOffset);
  const red = (value >> 10) & 0x1f;
  const green = (value >> 5) & 0x1f;
  const blue = value & 0x1f;

  output[writeOffset++] = (red << 3) | (red >> 2);
  output[writeOffset++] = (green << 3) | (green >> 2);
  output[writeOffset++] = (blue << 3) | (blue >> 2);
}

fs.writeFileSync(outputPath, output);
console.log(`${width}x${height} ${format} pixel_offset=${pixelOffset}`);
