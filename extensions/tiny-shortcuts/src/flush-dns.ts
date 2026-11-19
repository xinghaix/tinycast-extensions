import { showHUD } from "@raycast/api";
import { execFileSync } from "node:child_process";

export default async function Command() {
  if (process.env.TINYCAST_SYSTEM_DRY_RUN === "1") {
    await showHUD("🌐 [DRY_RUN] 已刷新 macOS DNS 缓存");
    return;
  }

  try {
    execFileSync("/usr/bin/dscacheutil", ["-flushcache"]);
  } catch {
    // continue to HUP mDNSResponder / escalated retry
  }

  try {
    execFileSync("/usr/bin/killall", ["-HUP", "mDNSResponder"], { stdio: "ignore" });
    await showHUD("🌐 DNS 缓存已刷新 (dscacheutil + mDNSResponder)");
    return;
  } catch {
    // Usually requires admin permission on macOS Sequoia
  }

  try {
    execFileSync("/usr/bin/osascript", [
      "-e",
      'do shell script "dscacheutil -flushcache; killall -HUP mDNSResponder" with administrator privileges',
    ]);
    await showHUD("🌐 已通过授权刷新 macOS DNS 缓存");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await showHUD(msg.includes("cancelled") || msg.includes("-128") ? "已取消刷新 DNS 缓存" : `刷新 DNS 失败: ${msg}`);
  }
}
