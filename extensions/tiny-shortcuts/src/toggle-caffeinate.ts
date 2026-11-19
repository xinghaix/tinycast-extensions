import { getPreferenceValues, showHUD, type LaunchProps } from "@raycast/api";
import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { formatDurationLabel, parseCaffeinateAction, parseDurationToSeconds } from "@shared/system-shortcuts";

interface CaffeinateArgs {
  duration?: string;
}

interface CaffeinatePrefs {
  defaultCaffeinateDuration?: string;
}

interface CaffeinateState {
  pid: number;
  startedAt: number;
  expiresAt: number | null;
  label: string;
}

function stateFilePath(): string {
  return `/tmp/tinycast-caffeinate-${process.getuid?.() ?? 0}.json`;
}

function isLiveCaffeinatePid(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    const comm = execFileSync("/bin/ps", ["-p", String(pid), "-o", "comm="], { encoding: "utf8" }).trim();
    return comm.includes("caffeinate");
  } catch {
    return false;
  }
}

function readActiveState(): CaffeinateState | null {
  const path = stateFilePath();
  if (!existsSync(path)) return null;
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as CaffeinateState;
    if (isLiveCaffeinatePid(parsed.pid)) {
      return parsed;
    }
  } catch {
    // ignore corrupt state
  }
  rmSync(path, { force: true });
  return null;
}

function stopActiveCaffeinate(): boolean {
  const state = readActiveState();
  if (!state) return false;
  try {
    process.kill(state.pid, "SIGTERM");
  } catch {
    // ignore
  }
  rmSync(stateFilePath(), { force: true });
  return true;
}

export default async function Command(props: LaunchProps<{ arguments: CaffeinateArgs }>) {
  const prefs = getPreferenceValues<CaffeinatePrefs>();
  const defaultDur = prefs.defaultCaffeinateDuration || "1h";
  const intent = parseCaffeinateAction(props.arguments?.duration, defaultDur);

  if (process.env.TINYCAST_SYSTEM_DRY_RUN === "1") {
    await showHUD(
      intent.kind === "off"
        ? "☕ [DRY_RUN] 已关闭防休眠 (Caffeinate)"
        : intent.kind === "status"
          ? "☕ [DRY_RUN] 防休眠未运行"
          : `☕ [DRY_RUN] 已开启防休眠 (${intent.kind === "on" ? intent.label : defaultDur})`,
    );
    return;
  }

  const active = readActiveState();

  if (intent.kind === "status") {
    if (!active) {
      await showHUD("☕ 当前未开启防休眠");
      return;
    }
    if (active.expiresAt === null) {
      await showHUD(`☕ 防休眠运行中（持续保持亮屏，PID ${active.pid}）`);
    } else {
      const remSec = Math.max(0, Math.round((active.expiresAt - Date.now()) / 1000));
      await showHUD(`☕ 防休眠运行中（剩余约 ${formatDurationLabel(remSec)}，PID ${active.pid}）`);
    }
    return;
  }

  if (intent.kind === "off" || (intent.kind === "toggle" && active !== null)) {
    const stopped = stopActiveCaffeinate();
    await showHUD(stopped ? "☕ 已关闭防休眠，恢复正常息屏策略" : "☕ 当前未开启防休眠");
    return;
  }

  // Turning ON
  if (active) {
    stopActiveCaffeinate();
  }

  let durationSeconds: number | null;
  let label: string;
  if (intent.kind === "on") {
    durationSeconds = intent.durationSeconds;
    label = intent.label;
  } else {
    durationSeconds = parseDurationToSeconds(defaultDur);
    label = durationSeconds ? formatDurationLabel(durationSeconds) : "持续保持唤醒";
  }

  const args = ["-di"];
  if (durationSeconds !== null) {
    args.push("-t", String(durationSeconds));
  }

  const child = spawn("/usr/bin/caffeinate", args, {
    detached: true,
    stdio: "ignore",
  });
  child.unref();

  await new Promise((resolve) => setTimeout(resolve, 25));

  if (child.pid) {
    const state: CaffeinateState = {
      pid: child.pid,
      startedAt: Date.now(),
      expiresAt: durationSeconds !== null ? Date.now() + durationSeconds * 1000 : null,
      label,
    };
    writeFileSync(stateFilePath(), JSON.stringify(state));
  }

  await showHUD(`☕ 已开启防休眠（${label}）`);
}
