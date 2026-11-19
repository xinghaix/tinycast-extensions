import { build } from "esbuild";
import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { builtinModules } from "node:module";
import { dirname, join, resolve } from "node:path";

const rootDir = resolve(dirname(new URL(import.meta.url).pathname), "..");
const extensionsDir = join(rootDir, "extensions");
const distRoot = join(rootDir, "dist");
const swiftSourceDir = join(rootDir, "native/devkit-app/Sources");
const buildTmpDir = join(distRoot, ".build-tmp");
const compiledBinaryPath = join(buildTmpDir, "tinycast-devkit");

const universalBuild = process.argv.includes("--universal") || process.env.BUILD_UNIVERSAL === "1";

const EXTERNAL_MODULES = [
  "@raycast/api",
  "react",
  "react/jsx-runtime",
  "react/jsx-dev-runtime",
  "react-dom",
  "node:*",
  ...builtinModules,
  ...builtinModules.map((m) => `node:${m}`),
];

function compileSwiftSlice(targetTriple, outputPath, swiftFiles) {
  execFileSync(
    "swiftc",
    [
      "-target",
      targetTriple,
      "-O",
      "-swift-version",
      "6",
      "-parse-as-library",
      "-lz",
      "-framework",
      "AppKit",
      "-framework",
      "SwiftUI",
      "-framework",
      "CryptoKit",
      "-framework",
      "CoreImage",
      "-framework",
      "CoreML",
      "-framework",
      "ImageIO",
      "-framework",
      "Security",
      "-framework",
      "UniformTypeIdentifiers",
      "-framework",
      "Vision",
      "-o",
      outputPath,
      ...swiftFiles,
    ],
    { cwd: rootDir, stdio: "inherit" },
  );
}

console.log("1. Generating native SF Symbol squircle PNG icons...");
execFileSync("swift", [join(rootDir, "scripts/generate-icons.swift")], {
  cwd: rootDir,
  stdio: "inherit",
});

console.log(`\n2. Compiling pure native SwiftUI + AppKit DevKit Studio (${universalBuild ? "Universal arm64 + x86_64" : process.arch}, macOS 15.0+)...`);
mkdirSync(buildTmpDir, { recursive: true });
const swiftFiles = readdirSync(swiftSourceDir)
  .filter((f) => f.endsWith(".swift"))
  .sort()
  .map((f) => join(swiftSourceDir, f));

if (universalBuild) {
  const armPath = join(buildTmpDir, "tinycast-devkit-arm64");
  const x64Path = join(buildTmpDir, "tinycast-devkit-x86_64");
  compileSwiftSlice("arm64-apple-macos15.0", armPath, swiftFiles);
  compileSwiftSlice("x86_64-apple-macos15.0", x64Path, swiftFiles);
  execFileSync("lipo", ["-create", armPath, x64Path, "-output", compiledBinaryPath], { stdio: "inherit" });
} else {
  const triple = process.arch === "x64" ? "x86_64-apple-macos15.0" : "arm64-apple-macos15.0";
  compileSwiftSlice(triple, compiledBinaryPath, swiftFiles);
}

execFileSync("codesign", ["--force", "--sign", "-", compiledBinaryPath], { stdio: "inherit" });
chmodSync(compiledBinaryPath, 0o755);
const archSummary = execFileSync("lipo", ["-archs", compiledBinaryPath], { encoding: "utf8" }).trim();
const binMb = (statSync(compiledBinaryPath).size / (1024 * 1024)).toFixed(2);
console.log(`   ✓ tinycast-devkit (${binMb} MB, archs: ${archSummary})`);

const extensionNames = ["tiny-devkit", "tiny-shortcuts"];

for (const extName of extensionNames) {
  const extSrcDir = join(extensionsDir, extName);
  const manifestPath = join(extSrcDir, "package.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

  const extDistDir = join(distRoot, extName);
  rmSync(extDistDir, { recursive: true, force: true });
  mkdirSync(extDistDir, { recursive: true });

  // Copy manifest, icons/assets, and compiled native binary
  writeFileSync(join(extDistDir, "package.json"), JSON.stringify(manifest, null, 2) + "\n");
  const assetsSrc = join(extSrcDir, "assets");
  const assetsDist = join(extDistDir, "assets");
  if (existsSync(assetsSrc)) {
    cpSync(assetsSrc, assetsDist, { recursive: true });
  } else {
    mkdirSync(assetsDist, { recursive: true });
  }
  const extBin = join(assetsDist, "tinycast-devkit");
  copyFileSync(compiledBinaryPath, extBin);
  chmodSync(extBin, 0o755);

  console.log(`\n3. Building extension "${manifest.title}" (${extName})...`);
  for (const cmd of manifest.commands) {
    const candidates = [
      join(extSrcDir, "src", `${cmd.name}.tsx`),
      join(extSrcDir, "src", `${cmd.name}.ts`),
    ];
    const entry = candidates.find((p) => existsSync(p));
    if (!entry) {
      throw new Error(`Missing source file for command "${cmd.name}" in ${extSrcDir}/src/`);
    }

    const outfile = join(extDistDir, `${cmd.name}.js`);
    await build({
      entryPoints: [entry],
      outfile,
      bundle: true,
      format: "cjs",
      platform: "node",
      target: ["es2022"],
      jsx: "automatic",
      jsxImportSource: "react",
      external: EXTERNAL_MODULES,
      alias: {
        "@shared": join(rootDir, "packages/shared/src"),
      },
      minify: true,
      legalComments: "none",
      sourcemap: false,
    });

    const kb = (statSync(outfile).size / 1024).toFixed(1);
    console.log(`   ✓ ${cmd.name}.js (${kb} KB) [${cmd.mode}]`);
  }
}

rmSync(buildTmpDir, { recursive: true, force: true });

console.log(`\nBuild complete! Ready-to-install extension folders:\n  - ${join(distRoot, "tiny-devkit")}\n  - ${join(distRoot, "tiny-shortcuts")}`);
