import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const rootDir = resolve(dirname(new URL(import.meta.url).pathname), "..");

const trackedFiles = execFileSync("git", ["ls-files", "-z"], {
  cwd: rootDir,
  encoding: "utf8",
})
  .split("\0")
  .filter(Boolean);

const failures = [];

const forbiddenTrackedPatterns = [
  { re: /^dist\//, reason: "Built dist/ output must not be tracked in git" },
  { re: /^release\//, reason: "Release archives must not be tracked in git" },
  { re: /^node_modules\//, reason: "node_modules/ must not be tracked in git" },
  { re: /(^|\/)\.DS_Store$/, reason: ".DS_Store must not be tracked in git" },
  { re: /\.(pem|key|p12)$/i, reason: "Private key material must not be tracked in git" },
];

// Exclude this scanner file from self-matching literals
const contentChecks = [
  { name: "macOS user home path", re: /\/Users\/[A-Za-z0-9._-]+\// },
  { name: "Linux user home path", re: /\/home\/[A-Za-z0-9._-]+\// },
  { name: "macOS private var folders path", re: /\/var\/folders\/[A-Za-z0-9/_-]+/ },
  { name: "Private key block", re: /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/ },
  { name: "GitHub PAT token", re: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b/ },
  { name: "AWS access key", re: /\bAKIA[0-9A-Z]{16}\b/ },
];

for (const rel of trackedFiles) {
  for (const rule of forbiddenTrackedPatterns) {
    if (rule.re.test(rel)) {
      failures.push(`${rel}: ${rule.reason}`);
    }
  }

  const fullPath = join(rootDir, rel);
  if (!existsSync(fullPath)) continue;

  // Validate JSON manifests strictly
  if (rel.endsWith(".json")) {
    try {
      JSON.parse(readFileSync(fullPath, "utf8"));
    } catch (err) {
      failures.push(`${rel}: Invalid JSON (${err.message})`);
    }
  }

  // Skip binary files & hygiene script itself
  if (/\.(png|jpg|jpeg|webp|icns|ico|zip)$/i.test(rel) || rel === "scripts/check-hygiene.mjs") {
    continue;
  }

  const text = readFileSync(fullPath, "utf8");
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    for (const check of contentChecks) {
      if (check.re.test(line)) {
        failures.push(`${rel}:${i + 1}: Matches forbidden pattern (${check.name})`);
      }
    }
  }
}

// Validate extension manifests against source entries and asset paths
for (const ext of ["tiny-devkit", "tiny-shortcuts"]) {
  const extDir = join(rootDir, "extensions", ext);
  const manifest = JSON.parse(readFileSync(join(extDir, "package.json"), "utf8"));
  if (!manifest.license) failures.push(`extensions/${ext}/package.json: Missing license field`);
  for (const cmd of manifest.commands ?? []) {
    if (cmd.icon && !existsSync(join(extDir, "assets", cmd.icon))) {
      failures.push(`extensions/${ext}/package.json: Missing icon assets/${cmd.icon}`);
    }
    const hasSrc =
      existsSync(join(extDir, "src", `${cmd.name}.ts`)) ||
      existsSync(join(extDir, "src", `${cmd.name}.tsx`));
    if (!hasSrc) {
      failures.push(`extensions/${ext}/package.json: Missing source for command ${cmd.name}`);
    }
  }
}

if (failures.length > 0) {
  console.error("Hygiene check failed:\n" + failures.map((f) => `  - ${f}`).join("\n"));
  process.exit(1);
}

console.log(`Hygiene check passed across ${trackedFiles.length} tracked files (clean manifests, no local paths or secrets).`);
