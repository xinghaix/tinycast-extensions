import { getPreferenceValues, getSelectedFinderItems, showHUD } from "@raycast/api";
import { execFileSync } from "node:child_process";
import { statSync } from "node:fs";
import { dirname } from "node:path";

function resolveFinderTargetDirectory(): string | null {
  try {
    const items = execFileSync(
      "/usr/bin/osascript",
      [
        "-e",
        'tell application "Finder" to get POSIX path of (insertion location as alias)',
      ],
      { encoding: "utf8" },
    ).trim();
    if (items) return items;
  } catch {
    // fallback below
  }
  return null;
}

export default async function Command() {
  const prefs = getPreferenceValues<{ terminalApp?: string }>();
  const appName = prefs.terminalApp || "Terminal";

  let targetDir: string | null = null;

  try {
    const selected = await getSelectedFinderItems();
    if (selected.length > 0 && selected[0].path) {
      const p = selected[0].path;
      const st = statSync(p);
      targetDir = st.isDirectory() ? p : dirname(p);
    }
  } catch {
    // fall back to insertion location
  }

  if (!targetDir) {
    targetDir = resolveFinderTargetDirectory();
  }

  if (!targetDir) {
    await showHUD("未检测到打开的 Finder 目录");
    return;
  }

  try {
    execFileSync("/usr/bin/open", ["-a", appName, targetDir]);
    await showHUD(`已在 ${appName} 中打开: ${targetDir}`);
  } catch (err) {
    await showHUD(`无法打开 ${appName}: ${err instanceof Error ? err.message : String(err)}`);
  }
}
