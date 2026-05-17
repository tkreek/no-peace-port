#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const sourceRoot = "original/extracted/america1/SFX";
const outputRoot = "game/assets/audio";

const phraseMap = new Map([
  ["Mexikaner", "Mexican"],
  ["Indianer", "Native"],
  ["Medizinmann Tanzen", "Medicine Man Chants"],
  ["Sterben Frau", "Female Deaths"],
  ["Sterben Mann", "Male Deaths"],
  ["Befehlshaber", "Commander"],
  ["Kommandant", "Commandant"],
  ["Krankenschwester", "Nurse"],
  ["Kavallerist", "Cavalry"],
  ["Infantrist", "Infantry"],
  ["Infanterist", "Infantry"],
  ["Siedler", "Settler"],
  ["Frau", "Woman"],
  ["Floss", "Raft"],
  ["ausführen", "command"],
  ["anklicken", "select"],
  ["auf Pferd", "mounted"],
  ["Goucho", "Gaucho"],
  ["Milizionär", "Militia"],
  ["Revolverheld", "Gunslinger"],
  ["Landarbeiter", "Farmhand"],
  ["Bandenchef", "Gang Leader"],
  ["Jäger", "Hunter"],
  ["Gewehrschütze", "Rifleman"],
  ["Gewehrchütze", "Rifleman"],
  ["Peitschenschwinger", "Whip Fighter"],
  ["Meuchelmörder", "Assassin"],
  ["Sprengstoffexperte", "Explosives Expert"],
  ["Barbier", "Barber"],
  ["Priester", "Priest"],
  ["Nonne", "Nun"],
  ["Bogenschütze", "Archer"],
  ["Brandpfeilschütze", "Fire Archer"],
  ["Häuptling", "Chief"],
  ["Krieger", "Warrior"],
  ["Messerwerfer", "Knife Thrower"],
  ["Speerkämpfer", "Spearman"],
  ["Medizinmann", "Medicine Man"],
  ["Sterben", "Death"],
  ["kurz", "Short"],
  ["lang", "Long"],
  ["Singen", "Chant"],
  ["Medizinann", "Medicine Man"],

  ["Sound ", ""],
  ["Angriff", "Attack"],
  ["Basis", "Base"],
  ["Keller", "Cellar"],
  ["Schnappsbrennerei", "Distillery"],
  ["Gebäude gebaut", "Building Complete"],
  ["Gebäude bauen", "Build Building"],
  ["Zusammenfallendes Gebäude groß", "Large Building Collapse"],
  ["Zusammenfallendes Gebäude klein", "Small Building Collapse"],
  ["Zusammenfallende Transporter", "Transport Collapse"],
  ["Dynamit Explosion", "Dynamite Explosion"],
  ["Dynamitschnur", "Dynamite Fuse"],
  ["Einheit fertig", "Unit Ready"],
  ["Upgrade fertig", "Upgrade Ready"],
  ["Drug-Store", "Drugstore"],
  ["Sprengstoffhütte", "Explosives Hut"],
  ["Wachturm", "Watchtower"],
  ["Ackerstück abernten", "Harvest Field"],
  ["Ackerstück", "Field"],
  ["Häuptlingszelt", "Chief Tent"],
  ["Ausbildungszelt", "Training Tent"],
  ["Bogenschützen", "Archers"],
  ["Einheit schwimmt", "Unit Swimming"],
  ["Feuerstelle", "Fire Pit"],
  ["Goldlager wird ausgeraubt", "Gold Storage Raided"],
  ["Goldlager", "Gold Storage"],
  ["Kanu schwimmt", "Canoe Swimming"],
  ["Kornspeicher", "Granary"],
  ["Medizinmannzelt", "Medicine Man Tent"],
  ["Wohnzelt", "Dwelling Tent"],
  ["Räucherstelle", "Smokehouse"],
  ["Tarnzelt", "Camouflage Tent"],
  ["Zelt der Alten", "Elders Tent"],
  ["Zauber Donner", "Spell Thunder"],
  ["Zauber Hagel", "Spell Hail"],
  ["Zauber Regen", "Spell Rain"],
  ["Zauber Sichtradius", "Spell Sight Radius"],
  ["Meldung auf Karte", "Map Alert"],
  ["Meldung", "Alert"],
  ["Nachricht anzeigen", "Show Message"],
  ["Neutrale Einheiten umfärben", "Recolor Neutral Units"],
  ["Bekehren", "Convert"],
  ["Heilen", "Heal"],
  ["heilen", "Heal"],
  ["Kommandatur", "Command Post"],
  ["ins Fort fliehen", "Flee To Fort"],
  ["Nonne heilen", "Nun Heal"],
  ["Priester bekehren", "Priest Convert"],
  ["Hauptquartier", "Headquarters"],
  ["Schlachthof", "Slaughterhouse"],
  ["Sägewerk", "Sawmill"],
  ["Ausbildungslager", "Training Camp"],
  ["Wohnhaus", "House"],
  ["Brücke", "Bridge"],
  ["Büffel sterben", "Buffalo Death"],
  ["Büffel", "Buffalo"],
  ["Fluß", "River"],
  ["Holz hacken", "Chop Wood"],
  ["kein Wohnraum mehr", "No Housing"],
  ["keine Ressourcen mehr", "No Resources"],
  ["Bevölkerungslimit erreicht", "Population Limit"],
  ["Mission gewonnen", "Mission Victory"],
  ["Mission verloren", "Mission Defeat"],
  ["Pferd Schnauben", "Horse Snort"],
  ["Pferd Sterben", "Horse Death"],
  ["Pferd Wiehern", "Horse Whinny"],
  ["Pferdegetrabe", "Horse Trot"],
  ["Gewehr laden", "Rifle Reload"],
  ["Gewehrschuss", "Rifle Shot"],
  ["Pistole laden", "Pistol Reload"],
  ["Pistolenschuss", "Pistol Shot"],
  ["Einschlag Kanonkugel", "Cannonball Impact"],
  ["Kanone bewegen", "Move Cannon"],
  ["Kanone", "Cannon"],
  ["Kaserne", "Barracks"],
  ["Kloster", "Monastery"],
  ["Transportwagen wird angegriffen", "Transport Wagon Attacked"],
  ["Wasserplatschen", "Water Splash"],
  ["Feld abgeerntet", "Field Harvested"],
  ["Gemuhe", "Cattle Moo"],
  ["Kuh sterben", "Cow Death"],
  ["Kuh Muh", "Cow Moo"],
  ["Tür", "Door"],
  ["Zustechen", "Stab"],
  ["Waffenfabrik", "Weapons Factory"],
  ["Bootshaus", "Boathouse"],
  ["Brennendes Gebäude", "Burning Building"],
  ["brennendes Gebäude", "Burning Building"],
  ["Handelsposten", "Trading Post"],
  ["Heu", "Hay"],
  ["Nicht bebaubar", "Cannot Build"],
  ["Zusammenfallende Einheit Wasser", "Unit Water Collapse"],
]);

const playable = [];
walk(sourceRoot, (filePath) => {
  const lower = filePath.toLowerCase();
  if (lower.endsWith(".mp3") || lower.endsWith(".wav") || /\.wav \(\d+\)$/i.test(lower)) {
    playable.push(filePath);
  }
});

for (const ownedDir of ["sfx", "voices", "missions", "misc"]) {
  fs.rmSync(path.join(outputRoot, ownedDir), { recursive: true, force: true });
}

const used = new Set();
for (const sourcePath of playable) {
  const relative = path.relative(sourceRoot, sourcePath);
  const parts = relative.split(path.sep);
  const targetDir = targetDirectory(parts);
  const ext = sourcePath.toLowerCase().endsWith(".mp3") ? ".mp3" : ".wav";
  const baseName = targetBaseName(parts, ext);
  const outputPath = uniquePath(path.join(outputRoot, targetDir, `${baseName}${ext}`), used);

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.copyFileSync(sourcePath, outputPath);
  console.log(`${relative} -> ${path.relative(outputRoot, outputPath)}`);
}

console.log(`Imported ${playable.length} audio files.`);

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

function targetDirectory(parts) {
  if (parts[0] === "Static") return "sfx";
  if (parts[0] === "Missions") return "missions";
  if (parts[0] === "Voices") {
    if (parts[1] === "Sterben Frau") return "voices/deaths/female";
    if (parts[1] === "Sterben Mann") return "voices/deaths/male";
    if (parts[1] === "Medizinmann Tanzen") return "voices/native/medicine_man_chants";
    return `voices/${slug(translate(parts[1] || "misc"))}`;
  }
  return "misc";
}

function targetBaseName(parts, ext) {
  if (parts[0] === "Missions") return missionName(parts.at(-1));
  if (parts[0] === "Voices") {
    const faction = parts[1];
    const fileStem = stripKnownExtension(parts.at(-1), ext);
    if (faction === "Sterben Frau" || faction === "Sterben Mann") return slug(translate(fileStem.replace(/^Sterben Frau |^Sterben Mann /, "")));
    if (faction === "Medizinmann Tanzen") return slug(translate(fileStem));
    return slug(translate(fileStem));
  }
  return slug(translate(stripKnownExtension(parts.at(-1), ext)));
}

function missionName(fileName) {
  const stem = path.basename(fileName, path.extname(fileName));
  if (/^des\d+$/i.test(stem)) return stem.toLowerCase().replace("des", "desperados_");
  if (/^ind\d+$/i.test(stem)) return stem.toLowerCase().replace("ind", "native_");
  if (/^mex\d+$/i.test(stem)) return stem.toLowerCase().replace("mex", "mexican_");
  if (/^usa\d+$/i.test(stem)) return stem.toLowerCase().replace("usa", "usa_");
  if (stem === "gewonnen") return "victory";
  if (stem === "verloren") return "defeat";
  return `mission_${slug(stem)}`;
}

function translate(value) {
  let translated = value;
  for (const [source, replacement] of [...phraseMap.entries()].sort((a, b) => b[0].length - a[0].length)) {
    translated = translated.replaceAll(source, replacement);
  }
  return translated;
}

function stripKnownExtension(fileName, ext) {
  if (fileName.toLowerCase().endsWith(ext)) return fileName.slice(0, -ext.length);
  return fileName.replace(/\.wav \(\d+\)$/i, " alternate");
}

function slug(value) {
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

function uniquePath(outputPath, used) {
  const parsed = path.parse(outputPath);
  let candidate = outputPath;
  let index = 2;
  while (used.has(candidate) || fs.existsSync(candidate)) {
    candidate = path.join(parsed.dir, `${parsed.name}_${index}${parsed.ext}`);
    index += 1;
  }
  used.add(candidate);
  return candidate;
}
