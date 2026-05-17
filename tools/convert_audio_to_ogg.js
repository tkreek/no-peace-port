#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const audioRoot = process.argv[2] || "game/assets/audio";
const quality = process.env.OGG_QUALITY || "5";
const manifestPath = path.join(audioRoot, "ogg_manifest.json");
const sourceExtensions = new Set([".wav", ".mp3"]);

const converted = [];
const skipped = [];

if (!fs.existsSync(audioRoot)) {
  console.error(`Audio root does not exist: ${audioRoot}`);
  process.exit(1);
}

const ffmpeg = spawnSync("ffmpeg", ["-version"], { encoding: "utf8" });
if (ffmpeg.status !== 0) {
  console.error("ffmpeg is required to convert audio to OGG.");
  process.exit(1);
}

const encoder = detectVorbisEncoder();
if (!encoder) {
  console.error("ffmpeg does not expose a Vorbis encoder. Cannot create Godot-friendly OGG Vorbis files.");
  process.exit(1);
}
console.log(`Using ffmpeg Vorbis encoder: ${encoder.name}`);

walk(audioRoot, (sourcePath) => {
  const extension = path.extname(sourcePath).toLowerCase();
  if (!sourceExtensions.has(extension)) return;

  const outputPath = replaceExtension(sourcePath, ".ogg");
  const sourceStat = fs.statSync(sourcePath);
  const outputStat = fs.existsSync(outputPath) ? fs.statSync(outputPath) : null;

  if (outputStat && outputStat.size > 0 && outputStat.mtimeMs >= sourceStat.mtimeMs) {
    skipped.push({ source: sourcePath, output: outputPath, reason: "up to date" });
    return;
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  const result = spawnSync(
    "ffmpeg",
    [
      "-y",
      "-hide_banner",
      "-loglevel",
      "error",
      "-i",
      sourcePath,
      "-map_metadata",
      "-1",
      "-vn",
      "-ac",
      "2",
      ...encoder.args,
      outputPath,
    ],
    { encoding: "utf8" }
  );

  if (result.status !== 0) {
    skipped.push({
      source: sourcePath,
      output: outputPath,
      reason: (result.stderr || result.stdout || "ffmpeg failed").trim(),
    });
    console.warn(`skip ${path.relative(audioRoot, sourcePath)}: ${skipped.at(-1).reason}`);
    return;
  }

  converted.push({
    source: sourcePath,
    output: outputPath,
    source_bytes: sourceStat.size,
    output_bytes: fs.statSync(outputPath).size,
  });
  console.log(`ok ${path.relative(audioRoot, sourcePath)} -> ${path.relative(audioRoot, outputPath)}`);
});

const manifest = {
  audio_root: audioRoot,
  quality,
  converted,
  skipped,
  totals: {
    converted: converted.length,
    skipped: skipped.length,
    source_bytes: converted.reduce((sum, item) => sum + item.source_bytes, 0),
    output_bytes: converted.reduce((sum, item) => sum + item.output_bytes, 0),
  },
};

fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
console.log("");
console.log(`Converted ${converted.length} file(s), skipped ${skipped.length}.`);
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

function replaceExtension(filePath, extension) {
  const parsed = path.parse(filePath);
  return path.join(parsed.dir, `${parsed.name}${extension}`);
}

function detectVorbisEncoder() {
  const encoders = spawnSync("ffmpeg", ["-hide_banner", "-encoders"], { encoding: "utf8" });
  if (encoders.status !== 0) return null;

  if (/\blibvorbis\b/.test(encoders.stdout)) {
    return { name: "libvorbis", args: ["-c:a", "libvorbis", "-q:a", quality] };
  }

  if (/\bvorbis\b/.test(encoders.stdout)) {
    return { name: "vorbis", args: ["-strict", "-2", "-c:a", "vorbis", "-q:a", quality] };
  }

  return null;
}
