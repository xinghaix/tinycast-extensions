export type CaffeinateIntent =
  | { kind: "toggle" }
  | { kind: "off" }
  | { kind: "status" }
  | { kind: "on"; durationSeconds: number | null; label: string };

export function parseCaffeinateAction(raw?: string, defaultDuration = "1h"): CaffeinateIntent {
  const s = (raw ?? "").trim().toLowerCase();
  if (!s) {
    return { kind: "toggle" };
  }
  if (s === "status" || s === "check" || s === "状态") {
    return { kind: "status" };
  }
  if (["off", "stop", "disable", "0", "关闭", "停止"].includes(s)) {
    return { kind: "off" };
  }
  if (["on", "forever", "inf", "infinite", "∞", "一直", "持续", "常亮"].includes(s)) {
    return { kind: "on", durationSeconds: null, label: "持续保持唤醒" };
  }

  const seconds = parseDurationToSeconds(s);
  if (seconds !== null) {
    return {
      kind: "on",
      durationSeconds: seconds,
      label: formatDurationLabel(seconds),
    };
  }

  // Fallback to defaultDuration if unrecognized? Better parse explicit or fall back safely to default only when empty.
  const fallback = parseDurationToSeconds(defaultDuration);
  return {
    kind: "on",
    durationSeconds: fallback,
    label: fallback ? formatDurationLabel(fallback) : "持续保持唤醒",
  };
}

export function parseDurationToSeconds(raw: string): number | null {
  const s = raw.trim().toLowerCase();
  if (!s) return null;
  if (s === "forever" || s === "infinite") return null;

  // Compound forms like `1h30m`, `2h`, `45m`, `90s`, or plain digits (treated as minutes)
  const compoundRe = /^(?:(\d+)\s*h(?:ours?|r)?)?(?:\s*(\d+)\s*m(?:in(?:utes?)?)?)?(?:\s*(\d+)\s*s(?:ec(?:onds?)?)?)?$/;
  const m = compoundRe.exec(s);
  if (m && (m[1] || m[2] || m[3])) {
    const hrs = Number(m[1] ?? "0");
    const mins = Number(m[2] ?? "0");
    const secs = Number(m[3] ?? "0");
    const total = hrs * 3600 + mins * 60 + secs;
    return total > 0 ? total : null;
  }

  if (/^\d+$/.test(s)) {
    const mins = Number(s);
    return mins > 0 ? mins * 60 : null;
  }

  return null;
}

export function formatDurationLabel(seconds: number): string {
  const mins = Math.round(seconds / 60);
  if (mins >= 60 && mins % 60 === 0) {
    return `${mins / 60} 小时`;
  }
  if (mins >= 60) {
    return `${Math.floor(mins / 60)} 小时 ${mins % 60} 分钟`;
  }
  if (seconds < 60) {
    return `${seconds} 秒`;
  }
  return `${mins} 分钟`;
}

export type PlainTextMode = "preserve" | "trim" | "singleline";

export function cleanPlainText(raw: string, modeRaw?: string): string {
  // Normalize CRLF/CR to LF and strip leading BOM + zero-width space noise
  let normalized = raw.replace(/\r\n?/g, "\n").replace(/\uFEFF/g, "");
  const mode = (modeRaw ?? "").trim().toLowerCase();
  if (mode === "trim" || mode === "tr") {
    normalized = normalized
      .split("\n")
      .map((line) => line.trim())
      .join("\n")
      .trim();
  } else if (mode === "singleline" || mode === "one" || mode === "1" || mode === "flatten") {
    normalized = normalized.replace(/\s+/g, " ").trim();
  }
  return normalized;
}
