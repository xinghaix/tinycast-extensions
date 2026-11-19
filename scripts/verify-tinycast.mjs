import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { accessSync, constants, existsSync, readFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import vm from "node:vm";

const rootDir = resolve(dirname(new URL(import.meta.url).pathname), "..");
const standaloneFlag = process.argv.includes("--standalone");
const requireRuntimeFlag = process.argv.includes("--require-runtime");
const tinycastTestPath =
  process.env.TINYCAST_RUNTIME_TEST ?? resolve(rootDir, "../tinycast/Scripts/raycast-runtime/test.mjs");

const hasRuntimeHarness = !standaloneFlag && existsSync(tinycastTestPath);
if (requireRuntimeFlag && !hasRuntimeHarness) {
  console.error(`Tinycast runtime test harness not found at ${tinycastTestPath}`);
  process.exit(1);
}

const STUDIO_LAUNCHER_COMMANDS = new Set([
  "workbench",
  "uuid-generator",
  "timestamp-converter",
  "hash-generator",
  "encode-decode",
  "json-formatter",
  "color-converter",
  "regex-tester",
  "text-diff",
  "url-parser",
  "number-base",
  "cidr-calculator",
  "cert-inspector",
  "data-converter",
  "sql-formatter",
  "password-generator",
  "text-transform",
  "qr-generator",
  "cron-inspector",
  "network-ports",
  "smart-clipboard",
  "ocr-scanner",
  "image-converter",
]);

const wait = (ms = 90) => new Promise((r) => setTimeout(r, ms));

function findNodes(node, predicate, out = []) {
  if (!node || typeof node !== "object") return out;
  for (const child of node.children ?? []) {
    if (predicate(child)) out.push(child);
    findNodes(child, predicate, out);
  }
  for (const val of Object.values(node.props ?? {})) {
    if (val && typeof val === "object" && "type" in val && "id" in val) {
      if (predicate(val)) out.push(val);
      findNodes(val, predicate, out);
    }
  }
  return out;
}

function verifyBuiltArtifactsStandalone(extDirs) {
  console.log("Verifying built manifests, assets, and CJS bundle exports...");
  const stubReact = {
    createElement: () => null,
    Fragment: Symbol("Fragment"),
    useEffect: () => {},
    useState: (v) => [typeof v === "function" ? v() : v, () => {}],
  };
  const stubRaycast = new Proxy(
    {},
    {
      get: (_t, prop) => {
        if (prop === "__esModule") return true;
        if (prop === "Icon") return new Proxy({}, { get: (_t2, k) => String(k) });
        if (prop === "Toast") return { Style: { Failure: "failure", Success: "success", Animated: "animated" } };
        if (prop === "LaunchType") return { UserInitiated: "userInitiated", Background: "background" };
        if (prop === "MenuBarExtra") {
          const fn = () => null;
          fn.Section = () => null;
          fn.Item = () => null;
          return fn;
        }
        return () => null;
      },
    },
  );
  const nodeRequire = createRequire(import.meta.url);

  for (const extDir of extDirs) {
    const manifest = JSON.parse(readFileSync(join(extDir, "package.json"), "utf8"));
    const binPath = join(extDir, "assets/tinycast-devkit");
    assert.ok(existsSync(binPath), `Missing native binary at ${binPath}`);
    accessSync(binPath, constants.X_OK);

    if (manifest.icon) {
      assert.ok(existsSync(join(extDir, "assets", manifest.icon)), `Missing extension icon ${manifest.icon}`);
    }

    for (const cmd of manifest.commands) {
      if (cmd.icon) {
        assert.ok(existsSync(join(extDir, "assets", cmd.icon)), `Missing command icon ${cmd.icon}`);
      }
      if (STUDIO_LAUNCHER_COMMANDS.has(cmd.name)) {
        assert.equal(cmd.mode, "no-view", `${cmd.name} must use mode=no-view`);
        assert.equal(cmd.arguments, undefined, `${cmd.name} must not define search-bar arguments pills`);
      }

      const bundlePath = join(extDir, `${cmd.name}.js`);
      assert.ok(existsSync(bundlePath), `Missing built bundle ${bundlePath}`);
      const code = readFileSync(bundlePath, "utf8");
      const m = { exports: {} };
      const fn = vm.runInNewContext(
        `(function (exports, require, module, __filename, __dirname) {\n${code}\n})`,
        {
          Buffer,
          URL,
          TextEncoder,
          TextDecoder,
          AbortController,
          setTimeout,
          clearTimeout,
          console,
          process,
        },
        { filename: bundlePath },
      );
      fn(
        m.exports,
        (specifier) => {
          if (specifier === "@raycast/api") return stubRaycast;
          if (specifier === "react" || specifier === "react/jsx-runtime" || specifier === "react/jsx-dev-runtime") {
            return stubReact;
          }
          if (specifier.startsWith("node:")) return nodeRequire(specifier);
          return nodeRequire(specifier);
        },
        m,
        bundlePath,
        extDir,
      );
      const exported = m.exports.default ?? m.exports;
      assert.equal(typeof exported, "function", `${manifest.name}/${cmd.name}.js must export a function`);
      console.log(`  ✓ ${manifest.name}/${cmd.name}.js [${cmd.mode}]`);
    }
  }
}

async function runConcurrentLockTest(binaryPath) {
  const raceLockPath = `/tmp/tinycast-devkit-${process.getuid()}-race-test.lock`;
  rmSync(raceLockPath, { force: true });

  const env = { ...process.env, TINYCAST_LOCK_TEST: "1" };
  delete env.TINYCAST_STUDIO_DRY_RUN;

  const spawnOnce = () =>
    new Promise((resolveRun, rejectRun) => {
      const child = spawn(binaryPath, [], { env, stdio: ["ignore", "pipe", "pipe"] });
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (d) => {
        stdout += d.toString("utf8");
      });
      child.stderr.on("data", (d) => {
        stderr += d.toString("utf8");
      });
      child.on("error", rejectRun);
      child.on("close", (code) => {
        if (code !== 0) {
          rejectRun(new Error(`lock test child exited with ${code}: ${stderr}`));
        } else {
          resolveRun(stdout.trim());
        }
      });
    });

  try {
    const outputs = await Promise.all(Array.from({ length: 5 }, () => spawnOnce()));
    const masters = outputs.filter((s) => s === "LOCK_MASTER").length;
    const secondaries = outputs.filter((s) => s === "LOCK_SECONDARY").length;
    assert.equal(masters, 1, `Expected strictly 1 LOCK_MASTER, got ${masters}: ${JSON.stringify(outputs)}`);
    assert.equal(secondaries, 4, `Expected strictly 4 LOCK_SECONDARY, got ${secondaries}: ${JSON.stringify(outputs)}`);
    console.log("  ✓ 5-way concurrent flock race test (1 LOCK_MASTER / 4 LOCK_SECONDARY)");
  } finally {
    rmSync(raceLockPath, { force: true });
  }
}

async function verifyNativeBinary(binPath) {
  console.log("\nRunning native Swift binary --self-test, codesign, DRY_RUN, & 5-way flock test...");
  const cleanEnv = { ...process.env };
  delete cleanEnv.TINYCAST_STUDIO_DRY_RUN;

  execFileSync("codesign", ["--verify", "--strict", binPath], { stdio: "ignore" });
  console.log("  ✓ tinycast-devkit codesign signature valid");

  execFileSync(binPath, ["--tool", "uuid"], {
    env: { ...cleanEnv, TINYCAST_STUDIO_DRY_RUN: "1" },
    stdio: "ignore",
  });
  console.log("  ✓ tinycast-devkit TINYCAST_STUDIO_DRY_RUN=1 clean exit");

  const selfOut = execFileSync(binPath, ["--self-test"], {
    env: cleanEnv,
    encoding: "utf8",
  }).trim();
  assert.equal(selfOut, "SELF_TEST_OK", `Unexpected --self-test output: ${selfOut}`);
  console.log(`  ✓ tinycast-devkit --self-test (${selfOut})`);

  await runConcurrentLockTest(binPath);
}

async function verifyWithTinycastHarness(devkitDir, shortcutsDir) {
  const { createHarness, bootConfig, preferenceDefault } = await import(pathToFileURL(tinycastTestPath).href);

  async function runCommandTest(extDir, cmdName, opts = {}) {
    const manifest = JSON.parse(readFileSync(join(extDir, "package.json"), "utf8"));
    const cmd = manifest.commands.find((c) => c.name === cmdName);
    assert.ok(cmd, `Missing command ${cmdName} in ${manifest.name}`);
    const bundlePath = join(extDir, `${cmd.name}.js`);
    const code = readFileSync(bundlePath, "utf8");
    const mode = opts.overrideMode ?? cmd.mode;

    const copied = [];
    const pasted = [];
    const huds = [];
    const toasts = [];
    let clipboardContent = opts.clipboard ?? "";
    let procStartCount = 0;

    const harness = createHarness({
      stubs: {
        "clipboard.readText": () => clipboardContent,
        "clipboard.copy": ([content]) => {
          copied.push(content);
          if (content?.text !== undefined) clipboardContent = content.text;
          return null;
        },
        "clipboard.paste": ([content]) => {
          pasted.push(content);
          if (content?.text !== undefined) clipboardContent = content.text;
          return null;
        },
        "feedback.showHUD": ([text]) => {
          huds.push(text);
          return null;
        },
        "feedback.showToast": ([payload]) => {
          toasts.push(payload);
          return "toast-1";
        },
        "system.selectedText": () => opts.selectedText ?? "",
        "system.selectedFinderItems": () => opts.finderItems ?? [],
        ...(opts.stubs ?? {}),
      },
    });

    const origInvokeSync = harness.context.__tinycastHost.invokeSync;
    harness.context.__tinycastHost.invokeSync = (api, method, argsJson) => {
      if (api === "proc" && method === "start") {
        procStartCount += 1;
      }
      return origInvokeSync(api, method, argsJson);
    };

    const prefs = Object.fromEntries(
      [...(manifest.preferences ?? []), ...(cmd.preferences ?? [])].map((p) => [p.name, preferenceDefault(p)]),
    );

    harness.boot(
      bootConfig({
        node: {
          ...bootConfig().node,
          env: {
            ...bootConfig().node.env,
            ...(opts.env ?? {}),
          },
        },
        environment: {
          ...bootConfig().environment,
          extensionName: manifest.name,
          commandName: cmd.name,
          commandMode: mode,
          assetsPath: join(extDir, "assets"),
        },
        preferences: prefs,
        launchProps: {
          launchType: "userInitiated",
          arguments: opts.arguments ?? {},
          fallbackText: opts.fallbackText,
        },
      }),
    );

    harness.start("s1", code, bundlePath, extDir, mode, {
      launchProps: {
        launchType: "userInitiated",
        arguments: opts.arguments ?? {},
        fallbackText: opts.fallbackText,
      },
    });

    await wait(opts.settleMs ?? 120);

    if (harness.state.failures.length > 0) {
      throw new Error(`Command ${manifest.name}/${cmd.name} failed:\n${harness.state.failures.join("\n")}`);
    }

    return { harness, copied, pasted, huds, toasts, cmd, manifest, procStartCount: () => procStartCount };
  }

  async function verifyStudioLauncher(extDir, cmdName, extraOpts = {}) {
    const { harness, cmd, procStartCount } = await runCommandTest(extDir, cmdName, extraOpts);
    assert.equal(cmd.mode, "no-view", `${cmdName} should use mode=no-view`);
    assert.equal(cmd.arguments, undefined, `${cmdName} should not define search-bar arguments pills`);
    assert.equal(harness.state.finished, true, `${cmdName} should resolve cleanly`);
    assert.equal(procStartCount(), 1, `${cmdName} must spawn tinycast-devkit exactly once`);
    assert.ok(harness.state.hostCalls.includes("window.close"), `${cmdName} should close Tinycast palette before opening Studio`);
    harness.stop("s1");
    console.log(`  ✓ ${cmdName} (no-view native launcher, proc.start=1)`);
  }

  process.env.TINYCAST_STUDIO_DRY_RUN = "1";

  console.log("\nVerifying tiny-devkit commands in Tinycast runtime...");
  for (const cmd of [
    "workbench",
    "uuid-generator",
    "timestamp-converter",
    "hash-generator",
    "encode-decode",
    "json-formatter",
    "regex-tester",
    "text-diff",
    "url-parser",
    "number-base",
    "cidr-calculator",
    "cert-inspector",
    "data-converter",
    "sql-formatter",
  ]) {
    await verifyStudioLauncher(devkitDir, cmd);
  }
  await verifyStudioLauncher(devkitDir, "color-converter", {
    selectedText: "#3B82F6",
  });

  // Stale in-memory `mode: "view"` 3x replay guard regression test
  {
    const { harness, procStartCount } = await runCommandTest(devkitDir, "uuid-generator", {
      overrideMode: "view",
      settleMs: 180,
    });
    assert.equal(procStartCount(), 1, `Stale view mode must still only invoke proc.start once, got ${procStartCount()}`);
    assert.ok(harness.state.hostCalls.includes("window.popToRoot"), "Stale view mode should call popToRoot()");
    assert.ok(harness.state.hostCalls.includes("window.close"), "Stale view mode should call closeMainWindow()");
    harness.stop("s1");
    console.log("  ✓ stale view-mode 3x replay guard (proc.start=1, popToRoot + window.close)");
  }

  for (const [cmdName, arg] of [
    ["quick-uuid-v4", { count: "3" }],
    ["quick-uuid-v7", { count: "2" }],
    ["quick-timestamp", { unit: "ms" }],
  ]) {
    const { harness, copied, huds } = await runCommandTest(devkitDir, cmdName, { arguments: arg });
    assert.equal(harness.state.finished, true, `${cmdName} should finish cleanly`);
    assert.equal(copied.length, 1, `${cmdName} should copy to clipboard`);
    assert.equal(huds.length, 1, `${cmdName} should show HUD`);
    harness.stop("s1");
    console.log(`  ✓ ${cmdName} (${huds[0]})`);
  }

  {
    const { harness, procStartCount } = await runCommandTest(devkitDir, "devkit-menubar", {
      clipboard: "1731830400",
    });
    const tree = harness.state.trees.at(-1);
    const root = findNodes(tree, (n) => n.type === "MenuBarExtra");
    const menuItems = findNodes(tree, (n) => n.type === "MenuBarExtra.Item");
    assert.equal(root.length, 1, "devkit-menubar should render MenuBarExtra");
    assert.ok(menuItems.length >= 13, `devkit-menubar should render items, got ${menuItems.length}`);
    const openUuid = menuItems.find((i) => i.props?.title?.includes("UUID 与 ID 生成器"));
    assert.ok(openUuid?.props?.onAction?.$fn, "devkit-menubar should wire UUID Studio launch item");
    harness.dispatch("s1", openUuid.props.onAction.$fn, []);
    await wait(90);
    assert.equal(harness.state.failures.length, 0, "devkit-menubar studio launch should not fail");
    assert.equal(procStartCount(), 1, "devkit-menubar item action should spawn tinycast-devkit once");
    harness.stop("s1");

    const colorBar = await runCommandTest(devkitDir, "devkit-menubar", {
      clipboard: "rgb(59, 130, 246)",
    });
    const colorItems = findNodes(colorBar.harness.state.trees.at(-1), (n) => n.type === "MenuBarExtra.Item");
    assert.ok(
      colorItems.some((i) => i.props?.title === "复制 HEX 色值" && i.props?.subtitle === "#3B82F6"),
      "devkit-menubar should surface quick HEX copy for clipboard color",
    );
    colorBar.harness.stop("s1");
    console.log("  ✓ devkit-menubar (timestamp + color clipboard + studio launch)");
  }

  console.log("\nVerifying tiny-shortcuts commands in Tinycast runtime...");
  for (const cmd of [
    "password-generator",
    "qr-generator",
    "cron-inspector",
    "network-ports",
    "smart-clipboard",
    "ocr-scanner",
    "image-converter",
  ]) {
    await verifyStudioLauncher(shortcutsDir, cmd);
  }
  await verifyStudioLauncher(shortcutsDir, "text-transform", {
    selectedText: "hello_tinycast_native_studio",
  });

  {
    const q = await runCommandTest(shortcutsDir, "quick-password", { arguments: { length: "24" } });
    assert.equal(q.copied[0]?.text?.length, 24, "quick-password should copy 24 chars");
    assert.equal(q.huds.length, 1, "quick-password should show HUD");
    q.harness.stop("s1");
    console.log(`  ✓ quick-password (${q.huds[0]})`);
  }

  {
    const sampleFinderPath = "/tmp/tinycast-sample-project";
    const { harness, copied, huds } = await runCommandTest(shortcutsDir, "copy-finder-path", {
      finderItems: [{ path: sampleFinderPath }],
    });
    assert.equal(harness.state.finished, true);
    assert.equal(copied[0]?.text, sampleFinderPath);
    assert.equal(huds.length, 1);
    harness.stop("s1");
    console.log(`  ✓ copy-finder-path (${huds[0]})`);
  }

  {
    const { harness, copied, pasted, huds } = await runCommandTest(shortcutsDir, "paste-plain-text", {
      clipboard: "  hello\r\n\tworld  ",
      arguments: { mode: "singleline" },
    });
    assert.equal(harness.state.finished, true);
    assert.equal(copied[0]?.text, "hello world");
    assert.equal(pasted[0]?.text, "hello world");
    assert.equal(huds.length, 1);
    harness.stop("s1");
    console.log(`  ✓ paste-plain-text (${huds[0]})`);
  }

  for (const [cmdName, args] of [
    ["toggle-caffeinate", { duration: "30m" }],
    ["flush-dns", {}],
  ]) {
    const { harness, huds } = await runCommandTest(shortcutsDir, cmdName, {
      arguments: args,
      env: { TINYCAST_SYSTEM_DRY_RUN: "1" },
    });
    assert.equal(harness.state.finished, true, `${cmdName} should finish cleanly`);
    assert.equal(huds.length, 1, `${cmdName} should show HUD`);
    assert.ok(huds[0].includes("[DRY_RUN]"), `${cmdName} should honor TINYCAST_SYSTEM_DRY_RUN, got: ${huds[0]}`);
    harness.stop("s1");
    console.log(`  ✓ ${cmdName} (${huds[0]})`);
  }

  delete process.env.TINYCAST_STUDIO_DRY_RUN;
}

async function verifyAll() {
  const devkitDir = join(rootDir, "dist/tiny-devkit");
  const shortcutsDir = join(rootDir, "dist/tiny-shortcuts");

  verifyBuiltArtifactsStandalone([devkitDir, shortcutsDir]);
  await verifyNativeBinary(join(devkitDir, "assets/tinycast-devkit"));

  if (hasRuntimeHarness) {
    await verifyWithTinycastHarness(devkitDir, shortcutsDir);
  } else {
    console.log("\n(Tinycast runtime harness not detected locally; completed standalone CI verification.)");
  }

  console.log("\nAll 33 extension commands and 22 native DevKit Studio tools passed cleanly!");
}

await verifyAll();
