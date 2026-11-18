import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { accessSync, constants, existsSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const rootDir = resolve(dirname(new URL(import.meta.url).pathname), "..");
const tinycastTestPath =
  process.env.TINYCAST_RUNTIME_TEST ?? resolve(rootDir, "../tinycast/Scripts/raycast-runtime/test.mjs");

if (!existsSync(tinycastTestPath)) {
  console.error(`Tinycast runtime test harness not found at ${tinycastTestPath}`);
  process.exit(1);
}

const { createHarness, bootConfig, preferenceDefault } = await import(pathToFileURL(tinycastTestPath).href);

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

async function runCommandTest(extDir, cmdName, opts = {}) {
  const manifest = JSON.parse(readFileSync(join(extDir, "package.json"), "utf8"));
  const cmd = manifest.commands.find((c) => c.name === cmdName);
  assert.ok(cmd, `Missing command ${cmdName} in ${manifest.name}`);
  const bundlePath = join(extDir, `${cmd.name}.js`);
  const code = readFileSync(bundlePath, "utf8");
  const mode = opts.overrideMode ?? cmd.mode;

  const copied = [];
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

  return { harness, copied, huds, toasts, cmd, manifest, procStartCount: () => procStartCount };
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

async function verifyAll() {
  const devkitDir = join(rootDir, "dist/tiny-devkit");
  const shortcutsDir = join(rootDir, "dist/tiny-shortcuts");

  // Ensure both extensions bundle executable tinycast-devkit binary
  for (const dir of [devkitDir, shortcutsDir]) {
    const bin = join(dir, "assets/tinycast-devkit");
    assert.ok(existsSync(bin), `Missing native binary at ${bin}`);
    accessSync(bin, constants.X_OK);
  }

  // Prevent real GUI windows from launching while testing JS command bundles
  process.env.TINYCAST_STUDIO_DRY_RUN = "1";

  console.log("Verifying tiny-devkit commands in Tinycast runtime...");
  for (const cmd of [
    "workbench",
    "uuid-generator",
    "timestamp-converter",
    "hash-generator",
    "encode-decode",
    "json-formatter",
  ]) {
    await verifyStudioLauncher(devkitDir, cmd);
  }
  await verifyStudioLauncher(devkitDir, "color-converter", {
    selectedText: "#3B82F6",
  });

  // Regression test: stale in-memory `mode: "view"` causes Tinycast's async-component adapt() to invoke
  // an AsyncFunction 3 times; verify single-shot guard limits proc.start to 1 and exits view via popToRoot + close.
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

  // devkit-menubar: renders MenuBarExtra items and launches native Studio cleanly
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
    const bundlePath = join(shortcutsDir, "open-in-terminal.js");
    const code = readFileSync(bundlePath, "utf8");
    const harness = createHarness();
    harness.boot(bootConfig());
    const exportedType = harness.call(`(() => {
      const m = { exports: {} };
      const fn = __tinycastCompile(${JSON.stringify(code)}, ${JSON.stringify(bundlePath)});
      fn(m.exports, (name) => {
        if (name === "@raycast/api" || name.startsWith("node:")) return {};
        return {};
      }, m, ${JSON.stringify(bundlePath)}, ${JSON.stringify(shortcutsDir)});
      return typeof (m.exports.default || m.exports);
    })()`);
    assert.equal(exportedType, "function", "open-in-terminal should export a function");
    console.log("  ✓ open-in-terminal (bundle & export verified)");
  }

  console.log("\nRunning native Swift binary --self-test & 5-way flock test...");
  delete process.env.TINYCAST_STUDIO_DRY_RUN;
  const binPath = join(devkitDir, "assets/tinycast-devkit");
  const selfOut = execFileSync(binPath, ["--self-test"], {
    encoding: "utf8",
  }).trim();
  assert.equal(selfOut, "SELF_TEST_OK", `Unexpected --self-test output: ${selfOut}`);
  console.log(`  ✓ tinycast-devkit --self-test (${selfOut})`);

  await runConcurrentLockTest(binPath);

  console.log("\nAll 20 extension commands, stale view replay guard, 5-way flock, and native DevKit Studio verified cleanly!");
}

await verifyAll();
