import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

const rootDir = resolve(dirname(new URL(import.meta.url).pathname), "..");
const targetRoot = join(homedir(), "Library/Application Support/com.abueammar.tinycast/extensions");

try {
  execFileSync("pkill", ["-f", "tinycast-devkit"], { stdio: "ignore" });
} catch {
  // No older instance running
}

// Remove legacy non-flock JSON lockfile if present
const legacyLock = join(tmpdir(), `tinycast-devkit-${process.getuid()}.json`);
rmSync(legacyLock, { force: true });

mkdirSync(targetRoot, { recursive: true });

for (const name of ["tiny-devkit", "tiny-shortcuts"]) {
  const src = join(rootDir, "dist", name);
  if (!existsSync(join(src, "package.json"))) {
    throw new Error(`Built extension missing at ${src}. Run "pnpm build" first.`);
  }
  const dest = join(targetRoot, name);
  rmSync(dest, { recursive: true, force: true });
  cpSync(src, dest, { recursive: true });
  const binPath = join(dest, "assets/tinycast-devkit");
  if (existsSync(binPath)) {
    chmodSync(binPath, 0o755);
  }
  console.log(`Installed ${name} -> ${dest}`);
}
