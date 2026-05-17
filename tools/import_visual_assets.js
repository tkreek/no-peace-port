#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const sourceRoots = process.argv.slice(2);
const roots = sourceRoots.length > 0 ? sourceRoots : ["original/extracted/america0", "original/extracted/america2"];
const outputRoot = "game/assets/visuals/imported";
const manifestPath = path.join(outputRoot, "manifest.json");

const supportedExtensions = new Set([".spr", ".pic", ".bmp"]);
const results = [];
let converted = 0;
let copied = 0;
let skipped = 0;

fs.rmSync(outputRoot, { recursive: true, force: true });

for (const root of roots) {
  if (!fs.existsSync(root)) {
    console.warn(`Skipping missing source root: ${root}`);
    continue;
  }

  walk(root, (sourcePath) => {
    const extension = path.extname(sourcePath).toLowerCase();
    if (!supportedExtensions.has(extension)) return;

    const relativePath = path.relative("original/extracted", sourcePath);
    const outputPath = path.join(outputRoot, englishOutputPath(relativePath));
    const record = { source: sourcePath, output: outputPath };

    try {
      fs.mkdirSync(path.dirname(outputPath), { recursive: true });

      if (extension === ".bmp") {
        convertWithMagick(sourcePath, outputPath);
        copied += 1;
      } else {
        const source = fs.readFileSync(sourcePath);
        const ppm = extension === ".spr" ? decodeRddx(sourcePath, source) : decodeRdic(sourcePath, source);
        writePngViaPpm(ppm, outputPath);
        converted += 1;
      }

      results.push({ ...record, status: "ok" });
      console.log(`ok ${relativePath}`);
    } catch (error) {
      skipped += 1;
      results.push({ ...record, status: "skipped", reason: error.message });
      console.warn(`skip ${relativePath}: ${error.message}`);
    }
  });
}

fs.mkdirSync(outputRoot, { recursive: true });
fs.writeFileSync(manifestPath, JSON.stringify(results, null, 2));

console.log("");
console.log(`Converted ${converted} indexed/sprite images.`);
console.log(`Converted ${copied} bitmap images.`);
console.log(`Skipped ${skipped} files.`);
console.log(`Manifest: ${manifestPath}`);

function walk(dir, callback) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(entryPath, callback);
    } else {
      callback(entryPath);
    }
  }
}

function decodeRddx(sourcePath, input) {
  if (input.subarray(0, 4).toString("ascii") !== "RDDX") {
    throw new Error("not an RDDX sprite sheet");
  }

  const width = input.readUInt32LE(4);
  const height = input.readUInt32LE(8);
  const format = input.subarray(16, 20).toString("ascii");
  if (format !== "P16B") {
    throw new Error(`unsupported RDDX pixel format ${format}`);
  }

  const pixelBytes = width * height * 2;
  const pixelOffset = input.length - pixelBytes;
  if (pixelOffset < 20) {
    throw new Error(`invalid RDDX dimensions in ${sourcePath}`);
  }

  const output = createPpmBuffer(width, height);
  let writeOffset = output.headerLength;

  for (let readOffset = pixelOffset; readOffset < input.length; readOffset += 2) {
    const value = input.readUInt16LE(readOffset);
    const red = (value >> 10) & 0x1f;
    const green = (value >> 5) & 0x1f;
    const blue = value & 0x1f;

    output.buffer[writeOffset++] = (red << 3) | (red >> 2);
    output.buffer[writeOffset++] = (green << 3) | (green >> 2);
    output.buffer[writeOffset++] = (blue << 3) | (blue >> 2);
  }

  return output.buffer;
}

function decodeRdic(sourcePath, input) {
  if (input.subarray(0, 4).toString("ascii") !== "RDIC") {
    throw new Error("not an RDIC image");
  }

  const width = input.readUInt32LE(4);
  const height = input.readUInt32LE(8);
  const pixelFormat = input.subarray(16, 20).toString("ascii");
  if (pixelFormat === "P16B") {
    return decodeRgb555(sourcePath, input, width, height, 20);
  }
  if (pixelFormat === "PRGB") {
    return decodeRgb24(sourcePath, input, width, height, 20);
  }
  if (pixelFormat !== "COLS") {
    throw new Error(`unsupported RDIC pixel format ${pixelFormat}`);
  }

  const paletteOffset = 20;
  const pixelTagOffset = paletteOffset + 256 * 3;
  const pixelTag = input.subarray(pixelTagOffset, pixelTagOffset + 4).toString("ascii");
  if (pixelTag !== "PRAW") {
    throw new Error(`unsupported RDIC pixel tag ${pixelTag}`);
  }

  const pixelOffset = pixelTagOffset + 4;
  const pixelCount = width * height;
  if (pixelOffset + pixelCount > input.length) {
    throw new Error(`invalid RDIC dimensions in ${sourcePath}`);
  }

  const output = createPpmBuffer(width, height);
  let writeOffset = output.headerLength;

  for (let index = 0; index < pixelCount; index += 1) {
    const colorOffset = paletteOffset + input[pixelOffset + index] * 3;
    output.buffer[writeOffset++] = input[colorOffset];
    output.buffer[writeOffset++] = input[colorOffset + 1];
    output.buffer[writeOffset++] = input[colorOffset + 2];
  }

  return output.buffer;
}

function decodeRgb555(sourcePath, input, width, height, pixelOffset) {
  const pixelBytes = width * height * 2;
  if (pixelOffset + pixelBytes > input.length) {
    throw new Error(`invalid RGB555 dimensions in ${sourcePath}`);
  }

  const output = createPpmBuffer(width, height);
  let writeOffset = output.headerLength;

  for (let readOffset = pixelOffset; readOffset < pixelOffset + pixelBytes; readOffset += 2) {
    const value = input.readUInt16LE(readOffset);
    const red = (value >> 10) & 0x1f;
    const green = (value >> 5) & 0x1f;
    const blue = value & 0x1f;

    output.buffer[writeOffset++] = (red << 3) | (red >> 2);
    output.buffer[writeOffset++] = (green << 3) | (green >> 2);
    output.buffer[writeOffset++] = (blue << 3) | (blue >> 2);
  }

  return output.buffer;
}

function decodeRgb24(sourcePath, input, width, height, pixelOffset) {
  const pixelBytes = width * height * 3;
  if (pixelOffset + pixelBytes > input.length) {
    throw new Error(`invalid RGB24 dimensions in ${sourcePath}`);
  }

  const output = createPpmBuffer(width, height);
  input.copy(output.buffer, output.headerLength, pixelOffset, pixelOffset + pixelBytes);
  return output.buffer;
}

function createPpmBuffer(width, height) {
  const header = `P6\n${width} ${height}\n255\n`;
  const headerLength = Buffer.byteLength(header);
  const buffer = Buffer.alloc(headerLength + width * height * 3);
  buffer.write(header, 0, "ascii");
  return { buffer, headerLength };
}

function writePngViaPpm(ppmBuffer, outputPath) {
  const tempPath = path.join(os.tmpdir(), `america-visual-${process.pid}-${Math.random().toString(36).slice(2)}.ppm`);
  fs.writeFileSync(tempPath, ppmBuffer);
  try {
    convertWithMagick(tempPath, outputPath);
  } finally {
    fs.rmSync(tempPath, { force: true });
  }
}

function convertWithMagick(inputPath, outputPath) {
  const result = spawnSync("magick", [inputPath, outputPath], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "magick conversion failed").trim());
  }
}

function replaceExtension(filePath, extension) {
  const parsed = path.parse(filePath);
  return path.join(parsed.dir, `${parsed.name}${extension}`);
}

function englishOutputPath(relativePath) {
  const withoutExtension = replaceExtension(relativePath, "");
  const parts = withoutExtension.split(path.sep).map(translatePathPart);
  return `${path.join(...parts)}.png`;
}

function translatePathPart(value) {
  const exact = new Map([
    ["Gfx", "graphics"],
    ["gfx", "graphics"],
    ["wiese", "meadow"],
    ["steppe", "steppe"],
    ["global", "global"],
    ["guids", "guids"],
    ["elemente", "elements"],
    ["baeume", "trees"],
    ["baeume2", "trees_2"],
    ["landschaft", "terrain"],
    ["menues", "menus"],
    ["einheiten", "units"],
    ["sonstigeicons", "misc_icons"],
    ["ladebild", "loading_screen"],
    ["ladebalken", "loading_bar"],
    ["abrechnung", "score_screen"],
    ["einstellungen", "settings"],
    ["ingameeinstellungen", "ingame_settings"],
    ["ingamemulti", "ingame_multiplayer"],
    ["kampagne", "campaign"],
    ["verbindung", "connection"],
    ["optionen", "options"],
    ["selectkampagne", "select_campaign"],
    ["selectmission", "select_mission"],
    ["selectnetname", "select_network_name"],
    ["selectplayer", "select_player"],
    ["selectgame", "select_game"],
    ["savemenu", "save_menu"],
    ["loadmenu", "load_menu"],
    ["mainmenu", "main_menu"],
    ["multimenu", "multiplayer_menu"],
    ["netmenu", "network_menu"],
    ["singlemenu", "single_player_menu"],
    ["selectmission", "select_mission"],
    ["selectkampagne", "select_campaign"],
    ["zeiger", "cursor"],
    ["feuer", "fire"],
    ["rauch", "smoke"],
    ["leiste", "status_bar"],
    ["leistelinks", "status_bar_left"],
    ["leisterechts", "status_bar_right"],
    ["leiste800600", "status_bar_800_600"],
    ["Usa", "usa"],
    ["usa", "usa"],
    ["mex", "mexican"],
    ["ind", "native"],
    ["des", "desperados"],
    ["bruecke02", "bridge_02"],
    ["anfang", "start"],
    ["fleischerei", "butcher"],
    ["cantina", "cantina"],
    ["minimu", "minimap_ui"],
    ["kleinwiese", "small_meadow"],
    ["kleinsteppe", "small_steppe"],
    ["Iconserstereihe", "first_row_icons"],
    ["KleineIcons", "small_icons"],
    ["SonstigeIcons", "misc_icons"],
    ["USAIcons", "usa_icons"],
    ["USAEinheiten", "usa_units"],
    ["MEXIcons", "mexican_icons"],
    ["mexeinheiten", "mexican_units"],
    ["desp_icons", "desperados_icons"],
  ]);

  if (exact.has(value)) return exact.get(value);

  const pictureList = value.match(/^Bilderliste__(\d+)$/);
  if (pictureList) return `sprite_sheet_${pictureList[1]}`;

  const picList = value.match(/^PICLIST(\d+)$/i);
  if (picList) return `sprite_sheet_${picList[1]}`;

  const smallSteppe = value.match(/^kleinsteppe(\d*)$/i);
  if (smallSteppe) return compactNumberSuffix("small_steppe", smallSteppe[1]);

  const smallMeadow = value.match(/^kleinwiese(\d*)$/i);
  if (smallMeadow) return compactNumberSuffix("small_meadow", smallMeadow[1]);

  const loadingScreen = value.match(/^ladebild(\d*)$/i);
  if (loadingScreen) return compactNumberSuffix("loading_screen", loadingScreen[1]);

  const tree = value.match(/^(\d+)_Baum$/);
  if (tree) return `tree_${tree[1]}`;

  return slugPathPart(value);
}

function compactNumberSuffix(baseName, suffix) {
  return suffix ? `${baseName}_${suffix}` : baseName;
}

function slugPathPart(value) {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/[^a-zA-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .replace(/_+/g, "_")
    .toLowerCase();
}
