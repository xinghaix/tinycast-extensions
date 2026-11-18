import { Clipboard, getSelectedFinderItems, showHUD } from "@raycast/api";
import { execFileSync } from "node:child_process";

export default async function Command() {
  let paths: string[] = [];

  try {
    const selected = await getSelectedFinderItems();
    paths = selected.map((i) => i.path).filter(Boolean);
  } catch {
    // ignore
  }

  if (paths.length === 0) {
    try {
      const current = execFileSync(
        "/usr/bin/osascript",
        ["-e", 'tell application "Finder" to get POSIX path of (insertion location as alias)'],
        { encoding: "utf8" },
      ).trim();
      if (current) paths = [current];
    } catch {
      // ignore
    }
  }

  if (paths.length === 0) {
    await showHUD("未检测到 Finder 选中项或窗口");
    return;
  }

  const output = paths.join("\n");
  await Clipboard.copy(output);
  await showHUD(
    paths.length === 1 ? `已复制路径: ${paths[0]}` : `已复制 ${paths.length} 个 Finder 路径`,
  );
}
