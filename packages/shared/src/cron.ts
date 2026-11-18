export interface CronFieldSpec {
  name: string;
  raw: string;
  values: number[];
  summary: string;
}

export interface ParsedCron {
  expression: string;
  normalized: string;
  hasSeconds: boolean;
  description: string;
  fields: CronFieldSpec[];
  nextRuns: Date[];
}

const MACROS: Record<string, string> = {
  "@yearly": "0 0 1 1 *",
  "@annually": "0 0 1 1 *",
  "@monthly": "0 0 1 * *",
  "@weekly": "0 0 * * 0",
  "@daily": "0 0 * * *",
  "@midnight": "0 0 * * *",
  "@hourly": "0 * * * *",
};

const MONTH_ALIASES: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

const DOW_ALIASES: Record<string, number> = {
  sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6,
};

const DOW_CN = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];

function parseTokenValue(raw: string, min: number, max: number, aliases?: Record<string, number>, wrap7to0 = false): number {
  const lower = raw.toLowerCase();
  let val = aliases && lower in aliases ? aliases[lower] : Number(raw);
  if (!Number.isInteger(val)) throw new Error(`无效 Cron 数值: ${raw}`);
  if (wrap7to0 && val === 7) val = 0;
  if (val < min || val > max) throw new Error(`Cron 数值越界 (${min}-${max}): ${raw}`);
  return val;
}

function expandField(
  raw: string,
  min: number,
  max: number,
  aliases?: Record<string, number>,
  wrap7to0 = false,
): number[] {
  const set = new Set<number>();
  const parts = raw.split(",");
  for (const part of parts) {
    const trimmed = part.trim();
    if (!trimmed) throw new Error(`无效 Cron 字段: ${raw}`);
    const [rangePart, stepStr] = trimmed.split("/");
    if (trimmed.split("/").length > 2) throw new Error(`无效步长语法: ${trimmed}`);
    const step = stepStr !== undefined ? Number(stepStr) : 1;
    if (!Number.isInteger(step) || step <= 0) throw new Error(`步长须为正整数: ${trimmed}`);

    if (rangePart === "*" || rangePart === "?") {
      for (let v = min; v <= max; v += step) set.add(wrap7to0 && v === 7 ? 0 : v);
    } else if (rangePart.includes("-")) {
      const [aRaw, bRaw] = rangePart.split("-");
      const start = parseTokenValue(aRaw, min, max, aliases, false);
      const end = parseTokenValue(bRaw, min, max, aliases, false);
      if (start > end) throw new Error(`范围起止无效: ${rangePart}`);
      for (let v = start; v <= end; v += step) set.add(wrap7to0 && v === 7 ? 0 : v);
    } else {
      const start = parseTokenValue(rangePart, min, max, aliases, wrap7to0);
      if (stepStr !== undefined) {
        for (let v = start; v <= max; v += step) set.add(wrap7to0 && v === 7 ? 0 : v);
      } else {
        set.add(start);
      }
    }
  }
  return Array.from(set).sort((a, b) => a - b);
}

function describeField(raw: string, unit: string, isDow = false): string {
  if (raw === "*" || raw === "?") return `每${unit}`;
  if (raw.startsWith("*/")) return `每 ${raw.slice(2)} ${unit}`;
  if (isDow) {
    const vals = expandField(raw, 0, 7, DOW_ALIASES, true);
    if (vals.length === 5 && vals.join(",") === "1,2,3,4,5") return "工作日 (周一至周五)";
    if (vals.length === 2 && vals.join(",") === "0,6") return "周末 (周六、周日)";
    return vals.map((v) => DOW_CN[v] ?? String(v)).join("、");
  }
  return raw;
}

function buildHumanDescription(
  secRaw: string | null,
  minRaw: string,
  hourRaw: string,
  domRaw: string,
  monthRaw: string,
  dowRaw: string,
): string {
  const parts: string[] = [];
  if (monthRaw !== "*") parts.push(`${monthRaw} 月`);
  if (dowRaw !== "*" && dowRaw !== "?") parts.push(describeField(dowRaw, "天", true));
  if (domRaw !== "*" && domRaw !== "?") parts.push(`每月第 ${domRaw} 日`);

  if (hourRaw === "*" && minRaw === "*" && (!secRaw || secRaw === "*")) {
    parts.push(secRaw ? "每秒执行" : "每分钟执行");
  } else if (hourRaw === "*" && minRaw.startsWith("*/")) {
    parts.push(`每 ${minRaw.slice(2)} 分钟执行`);
  } else if (hourRaw === "*") {
    parts.push(`每小时第 ${minRaw} 分`);
  } else if (/^\d+$/.test(hourRaw) && /^\d+$/.test(minRaw)) {
    const hh = hourRaw.padStart(2, "0");
    const mm = minRaw.padStart(2, "0");
    const ss = secRaw && /^\d+$/.test(secRaw) ? `:${secRaw.padStart(2, "0")}` : "";
    parts.push(`在 ${hh}:${mm}${ss}`);
  } else {
    parts.push(`时(${hourRaw}) 分(${minRaw})${secRaw ? ` 秒(${secRaw})` : ""}`);
  }
  return parts.join(" · ");
}

export function parseCron(expression: string, options?: { from?: Date; count?: number }): ParsedCron {
  const trimmed = expression.trim();
  if (!trimmed) throw new Error("请输入 Cron 表达式");

  const macroExpanded = MACROS[trimmed.toLowerCase()];
  const normalized = (macroExpanded ?? trimmed).replace(/\s+/g, " ");
  const tokens = normalized.split(" ");
  if (tokens.length !== 5 && tokens.length !== 6) {
    throw new Error(`需要 5 段 (分 时 日 月 周) 或 6 段 (秒 分 时 日 月 周) 表达式，当前为 ${tokens.length} 段`);
  }

  const hasSeconds = tokens.length === 6;
  const [secRaw, minRaw, hourRaw, domRaw, monthRaw, dowRaw] = hasSeconds
    ? tokens
    : ["0", tokens[0], tokens[1], tokens[2], tokens[3], tokens[4]];

  const seconds = expandField(secRaw, 0, 59);
  const minutes = expandField(minRaw, 0, 59);
  const hours = expandField(hourRaw, 0, 23);
  const doms = expandField(domRaw, 1, 31);
  const months = expandField(monthRaw, 1, 12, MONTH_ALIASES);
  const dows = expandField(dowRaw, 0, 7, DOW_ALIASES, true);

  const secSet = new Set(seconds);
  const minSet = new Set(minutes);
  const hourSet = new Set(hours);
  const domSet = new Set(doms);
  const monthSet = new Set(months);
  const dowSet = new Set(dows);

  const domWild = domRaw === "*" || domRaw === "?";
  const dowWild = dowRaw === "*" || dowRaw === "?";

  const from = options?.from ?? new Date();
  const count = options?.count ?? 10;
  const nextRuns: Date[] = [];

  // Start from the next whole second (or minute when 5-field)
  const cursor = new Date(from.getTime());
  cursor.setMilliseconds(0);
  if (hasSeconds) {
    cursor.setSeconds(cursor.getSeconds() + 1);
  } else {
    cursor.setSeconds(0);
    cursor.setMinutes(cursor.getMinutes() + 1);
  }

  const maxIterations = hasSeconds ? 200_000 : 525_600; // Up to 1 year of minutes
  const stepMs = hasSeconds ? 1000 : 60_000;

  let iter = 0;
  const maxYear = from.getFullYear() + 5;

  while (nextRuns.length < count && iter < maxIterations && cursor.getFullYear() <= maxYear) {
    iter++;
    const month = cursor.getMonth() + 1;
    if (!monthSet.has(month)) {
      cursor.setMonth(cursor.getMonth() + 1, 1);
      cursor.setHours(0, 0, 0, 0);
      continue;
    }

    const dom = cursor.getDate();
    const dow = cursor.getDay();
    const dayMatches =
      domWild && dowWild
        ? true
        : domWild
          ? dowSet.has(dow)
          : dowWild
            ? domSet.has(dom)
            : domSet.has(dom) || dowSet.has(dow); // Standard Vixie Cron OR semantics

    if (!dayMatches) {
      cursor.setDate(cursor.getDate() + 1);
      cursor.setHours(0, 0, 0, 0);
      continue;
    }

    const hour = cursor.getHours();
    if (!hourSet.has(hour)) {
      cursor.setHours(hour + 1, 0, 0, 0);
      continue;
    }

    const minute = cursor.getMinutes();
    if (!minSet.has(minute)) {
      cursor.setMinutes(minute + 1, 0, 0);
      continue;
    }

    const second = cursor.getSeconds();
    if (hasSeconds && !secSet.has(second)) {
      cursor.setTime(cursor.getTime() + 1000);
      continue;
    }

    nextRuns.push(new Date(cursor.getTime()));
    cursor.setTime(cursor.getTime() + stepMs);
  }

  const fields: CronFieldSpec[] = [];
  if (hasSeconds) fields.push({ name: "秒 (Second)", raw: secRaw, values: seconds, summary: describeField(secRaw, "秒") });
  fields.push(
    { name: "分 (Minute)", raw: minRaw, values: minutes, summary: describeField(minRaw, "分钟") },
    { name: "时 (Hour)", raw: hourRaw, values: hours, summary: describeField(hourRaw, "小时") },
    { name: "日 (Day)", raw: domRaw, values: doms, summary: describeField(domRaw, "日") },
    { name: "月 (Month)", raw: monthRaw, values: months, summary: describeField(monthRaw, "月") },
    { name: "周 (Weekday)", raw: dowRaw, values: dows, summary: describeField(dowRaw, "周", true) },
  );

  return {
    expression: trimmed,
    normalized,
    hasSeconds,
    description: buildHumanDescription(hasSeconds ? secRaw : null, minRaw, hourRaw, domRaw, monthRaw, dowRaw),
    fields,
    nextRuns,
  };
}

export const COMMON_CRON_PRESETS: Array<{ title: string; expression: string; note: string }> = [
  { title: "每分钟执行", expression: "* * * * *", note: "Every minute" },
  { title: "每 5 分钟执行", expression: "*/5 * * * *", note: "Every 5 minutes" },
  { title: "每小时整点", expression: "0 * * * *", note: "Hourly at :00" },
  { title: "每天凌晨 00:00", expression: "0 0 * * *", note: "Daily midnight" },
  { title: "工作日早 9:00", expression: "0 9 * * 1-5", note: "Mon–Fri 09:00" },
  { title: "工作日 9:00–18:00 每 15 分钟", expression: "*/15 9-18 * * 1-5", note: "Work hours polling" },
  { title: "每周一早上 8:30", expression: "30 8 * * 1", note: "Weekly Monday 08:30" },
  { title: "每月 1 号凌晨 02:00", expression: "0 2 1 * *", note: "Monthly 1st 02:00" },
];
