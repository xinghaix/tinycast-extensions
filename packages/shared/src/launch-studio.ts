import { closeMainWindow, environment, getSelectedText, popToRoot, showToast, Toast } from "@raycast/api";
import { spawn } from "node:child_process";
import { accessSync, chmodSync, constants, existsSync } from "node:fs";
import { join } from "node:path";

export type StudioToolId =
  | "smart"
  | "uuid"
  | "timestamp"
  | "hash"
  | "codec"
  | "json"
  | "color"
  | "regex"
  | "diff"
  | "url"
  | "radix"
  | "cidr"
  | "cert"
  | "data"
  | "sql"
  | "ocr"
  | "image"
  | "password"
  | "text"
  | "qr"
  | "cron"
  | "network";

export interface LaunchStudioOptions {
  tool: StudioToolId;
  captureSelection?: boolean;
  /** Set false when launched from a MenuBarExtra item rather than the main search palette. */
  closePalette?: boolean;
}

// Guards against stale manifest `mode: "view"` 3x async-component replay or rapid double triggers
// inside the same Tinycast runtime session.
let commandLaunchedInSession = false;
let lastMenuLaunchAt = 0;

export async function launchDevKitStudio(options: LaunchStudioOptions): Promise<void> {
  if (options.closePalette !== false) {
    if (commandLaunchedInSession) return;
    commandLaunchedInSession = true;
  } else {
    const now = Date.now();
    if (now - lastMenuLaunchAt < 350) return;
    lastMenuLaunchAt = now;
  }

  const binaryPath = join(environment.assetsPath, "tinycast-devkit");
  if (!existsSync(binaryPath)) {
    await showToast({
      style: Toast.Style.Failure,
      title: "DevKit 原生组件缺失",
      message: `未找到 ${binaryPath}，请重新运行 pnpm build 与安装。`,
    });
    return;
  }

  try {
    accessSync(binaryPath, constants.X_OK);
  } catch {
    try {
      chmodSync(binaryPath, 0o755);
    } catch {
      // Ignore if read-only
    }
  }

  const args: string[] = ["--tool", options.tool];
  if (options.captureSelection) {
    try {
      const selected = await getSelectedText();
      if (selected && selected.trim().length > 0 && selected.length <= 65536) {
        args.push("--selected", Buffer.from(selected, "utf8").toString("base64"));
      }
    } catch {
      // Accessibility selection capture is best-effort
    }
  }

  if (options.closePalette !== false) {
    if (environment.commandMode === "view") {
      try {
        await popToRoot();
      } catch {
        // Ignore if not currently pushed
      }
    }
    await closeMainWindow();
  }

  const child = spawn(binaryPath, args, {
    detached: true,
    stdio: "ignore",
  });
  child.unref();

  // Tinycast's node-shims.js schedules child_process _start on queueMicrotask;
  // wait briefly before returning from a no-view command so the runtime context stays alive until spawned.
  await new Promise((resolve) => setTimeout(resolve, 25));
}
