export type TimestampUnit = "s" | "ms" | "us" | "ns";

export interface ParsedTimestamp {
  date: Date;
  detectedKind: string;
  sourceUnit?: TimestampUnit;
  fractionalNanoseconds?: bigint;
  isLive: boolean;
}

export interface TimestampEntry {
  id: string;
  category: "unix" | "standard" | "timezone" | "calendar" | "code";
  title: string;
  value: string;
  badge: string;
  description?: string;
}

export interface TimestampReport {
  parsed: ParsedTimestamp;
  entries: TimestampEntry[];
  relativeLabel: string;
  isoWeek: string;
  dayOfYear: number;
  quarter: number;
  isLeapYear: boolean;
}

export const DEFAULT_WORLD_TIMEZONES: Array<{ zone: string; label: string }> = [
  { zone: "UTC", label: "UTC · 协调世界时" },
  { zone: "Asia/Shanghai", label: "Asia/Shanghai · 北京/上海" },
  { zone: "Asia/Tokyo", label: "Asia/Tokyo · 东京" },
  { zone: "America/New_York", label: "America/New_York · 纽约" },
  { zone: "America/Los_Angeles", label: "America/Los_Angeles · 洛杉矶" },
  { zone: "Europe/London", label: "Europe/London · 伦敦" },
  { zone: "Europe/Berlin", label: "Europe/Berlin · 柏林" },
  { zone: "Asia/Singapore", label: "Asia/Singapore · 新加坡" },
];

function pad2(n: number): string {
  return String(Math.trunc(Math.abs(n))).padStart(2, "0");
}

function pad3(n: number): string {
  return String(Math.trunc(Math.abs(n))).padStart(3, "0");
}

function pad4(n: number): string {
  return String(n).padStart(4, "0");
}

function formatOffset(offsetMinutesEast: number): string {
  if (offsetMinutesEast === 0) return "+00:00";
  const sign = offsetMinutesEast >= 0 ? "+" : "-";
  const abs = Math.abs(offsetMinutesEast);
  return `${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`;
}

export function formatLocalIso(date: Date): string {
  const offsetEast = -date.getTimezoneOffset();
  return `${pad4(date.getFullYear())}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}T${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}.${pad3(date.getMilliseconds())}${formatOffset(offsetEast)}`;
}

export function formatLocalDateTime(date: Date, withMs = false): string {
  const base = `${pad4(date.getFullYear())}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
  return withMs ? `${base}.${pad3(date.getMilliseconds())}` : base;
}

export function formatUtcDateTime(date: Date, withMs = false): string {
  const base = `${pad4(date.getUTCFullYear())}-${pad2(date.getUTCMonth() + 1)}-${pad2(date.getUTCDate())} ${pad2(date.getUTCHours())}:${pad2(date.getUTCMinutes())}:${pad2(date.getUTCSeconds())}`;
  return withMs ? `${base}.${pad3(date.getUTCMilliseconds())}` : base;
}

export function formatInTimezone(date: Date, timeZone: string): { formatted: string; offset: string } {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(date);
    const map = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    const formatted = `${map.year}-${map.month}-${map.day} ${map.hour}:${map.minute}:${map.second}`;

    const tzParts = new Intl.DateTimeFormat("en-US", {
      timeZone,
      timeZoneName: "shortOffset",
    }).formatToParts(date);
    const offset = tzParts.find((p) => p.type === "timeZoneName")?.value ?? timeZone;
    return { formatted, offset };
  } catch {
    return { formatted: "Invalid Timezone", offset: timeZone };
  }
}

function getIsoWeek(date: Date): string {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${pad2(week)}`;
}

function getDayOfYear(date: Date): number {
  const start = new Date(date.getFullYear(), 0, 0);
  const diff = date.getTime() - start.getTime() + (start.getTimezoneOffset() - date.getTimezoneOffset()) * 60000;
  return Math.floor(diff / 86400000);
}

export function formatRelativeTime(target: Date, now: Date): string {
  const diffMs = target.getTime() - now.getTime();
  const absSec = Math.round(Math.abs(diffMs) / 1000);
  if (absSec < 2) return "刚刚 (Just now)";
  const suffix = diffMs >= 0 ? "后" : "前";
  if (absSec < 60) return `${absSec} 秒${suffix}`;
  const mins = Math.floor(absSec / 60);
  if (mins < 60) return `${mins} 分钟${suffix}`;
  const hours = Math.floor(mins / 60);
  const remMins = mins % 60;
  if (hours < 24) return remMins > 0 ? `${hours} 小时 ${remMins} 分钟${suffix}` : `${hours} 小时${suffix}`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} 天${suffix}`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months} 个月${suffix}`;
  const years = (days / 365.25).toFixed(1).replace(/\.0$/, "");
  return `${years} 年${suffix}`;
}

function applyRelativeOffset(base: Date, sign: 1 | -1, amount: number, unit: string): Date | null {
  const d = new Date(base.getTime());
  switch (unit) {
    case "ms":
      d.setTime(d.getTime() + sign * amount);
      return d;
    case "s":
    case "sec":
    case "secs":
    case "second":
    case "seconds":
      d.setTime(d.getTime() + sign * amount * 1000);
      return d;
    case "m":
    case "min":
    case "mins":
    case "minute":
    case "minutes":
      d.setTime(d.getTime() + sign * amount * 60_000);
      return d;
    case "h":
    case "hr":
    case "hrs":
    case "hour":
    case "hours":
      d.setTime(d.getTime() + sign * amount * 3_600_000);
      return d;
    case "d":
    case "day":
    case "days":
      d.setDate(d.getDate() + sign * amount);
      return d;
    case "w":
    case "wk":
    case "wks":
    case "week":
    case "weeks":
      d.setDate(d.getDate() + sign * amount * 7);
      return d;
    case "M":
    case "mo":
    case "month":
    case "months":
      d.setMonth(d.getMonth() + sign * amount);
      return d;
    case "y":
    case "yr":
    case "yrs":
    case "year":
    case "years":
      d.setFullYear(d.getFullYear() + sign * amount);
      return d;
    default:
      return null;
  }
}

function parseAnchorKeyword(keyword: string, now: Date): Date | null {
  const k = keyword.trim().toLowerCase();
  if (k === "now") return new Date(now.getTime());
  if (k === "today") return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  if (k === "tomorrow") return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 0);
  if (k === "yesterday") return new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1, 0, 0, 0, 0);
  if (k === "start of day" || k === "sod") return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  if (k === "end of day" || k === "eod") return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
  if (k === "start of week" || k === "sow") {
    const day = now.getDay();
    const diffToMonday = day === 0 ? -6 : 1 - day;
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + diffToMonday, 0, 0, 0, 0);
  }
  if (k === "start of month" || k === "som") return new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);
  if (k === "end of month" || k === "eom") return new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
  if (k === "start of year" || k === "soy") return new Date(now.getFullYear(), 0, 1, 0, 0, 0, 0);
  if (k === "end of year" || k === "eoy") return new Date(now.getFullYear(), 11, 31, 23, 59, 59, 999);
  return null;
}

export function parseTimestampInput(raw: string, now: Date = new Date()): ParsedTimestamp | null {
  const input = raw.trim();
  if (!input) {
    return {
      date: now,
      detectedKind: "当前实时时间 (Live)",
      isLive: true,
    };
  }

  // 1. Explicit compact YYYYMMDDHHmmss (14 digits) or YYYYMMDD (8 digits) if realistic calendar date
  if (/^\d{14}$/.test(input)) {
    const y = Number(input.slice(0, 4));
    const m = Number(input.slice(4, 6));
    const d = Number(input.slice(6, 8));
    const H = Number(input.slice(8, 10));
    const M = Number(input.slice(10, 12));
    const S = Number(input.slice(12, 14));
    if (y >= 1970 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31 && H <= 23 && M <= 59 && S <= 59) {
      const dt = new Date(y, m - 1, d, H, M, S, 0);
      if (dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d) {
        return { date: dt, detectedKind: "紧凑日期时间 (YYYYMMDDHHmmss)", isLive: false };
      }
    }
  }
  if (/^\d{8}$/.test(input)) {
    const y = Number(input.slice(0, 4));
    const m = Number(input.slice(4, 6));
    const d = Number(input.slice(6, 8));
    if (y >= 1970 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      const dt = new Date(y, m - 1, d, 0, 0, 0, 0);
      if (dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d) {
        return { date: dt, detectedKind: "紧凑日期 (YYYYMMDD)", isLive: false };
      }
    }
  }

  // 2. Numeric Unix timestamp (integer or decimal, optional negative sign)
  if (/^-?\d+(\.\d+)?$/.test(input)) {
    const isInt = !input.includes(".");
    if (isInt) {
      const big = BigInt(input);
      const abs = big < 0n ? -big : big;
      if (abs >= 100_000_000_000_000_000n) {
        const ms = Number(big / 1_000_000n);
        const dt = new Date(ms);
        if (!Number.isNaN(dt.getTime())) {
          return {
            date: dt,
            detectedKind: "Unix 纳秒 (ns)",
            sourceUnit: "ns",
            fractionalNanoseconds: big,
            isLive: false,
          };
        }
      }
      if (abs >= 100_000_000_000_000n) {
        const ms = Number(big / 1_000n);
        const dt = new Date(ms);
        if (!Number.isNaN(dt.getTime())) {
          return {
            date: dt,
            detectedKind: "Unix 微秒 (μs)",
            sourceUnit: "us",
            fractionalNanoseconds: big * 1000n,
            isLive: false,
          };
        }
      }
      if (abs >= 100_000_000_000n) {
        const dt = new Date(Number(big));
        if (!Number.isNaN(dt.getTime())) {
          return { date: dt, detectedKind: "Unix 毫秒 (ms)", sourceUnit: "ms", isLive: false };
        }
      }
      const dt = new Date(Number(big) * 1000);
      if (!Number.isNaN(dt.getTime())) {
        return { date: dt, detectedKind: "Unix 秒 (s)", sourceUnit: "s", isLive: false };
      }
    } else {
      const num = Number(input);
      if (Number.isFinite(num)) {
        const abs = Math.abs(num);
        const isMs = abs >= 1e11;
        const dt = new Date(isMs ? num : num * 1000);
        if (!Number.isNaN(dt.getTime())) {
          return {
            date: dt,
            detectedKind: isMs ? "Unix 毫秒 (浮点 ms)" : "Unix 秒 (浮点 s)",
            sourceUnit: isMs ? "ms" : "s",
            isLive: false,
          };
        }
      }
    }
  }

  // 3. Relative anchor or offset expressions: `now`, `+2h`, `now - 3d`, `today+1w`
  const anchor = parseAnchorKeyword(input, now);
  if (anchor) {
    return { date: anchor, detectedKind: `相对时间 (${input})`, isLive: false };
  }

  const relOnly = input.match(/^([+-])\s*(\d+)\s*(ms|sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days|wk|wks|week|weeks|mo|month|months|yr|yrs|year|years|s|m|h|d|w|M|y)$/);
  if (relOnly) {
    const sign = relOnly[1] === "-" ? -1 : 1;
    const amount = Number(relOnly[2]);
    const shifted = applyRelativeOffset(now, sign, amount, relOnly[3]);
    if (shifted) {
      return { date: shifted, detectedKind: `相对偏移 (now ${relOnly[1]}${amount}${relOnly[3]})`, isLive: false };
    }
  }

  const anchorOffset = input.match(
    /^(now|today|tomorrow|yesterday|sod|eod|sow|som|eom|soy|eoy)\s*([+-])\s*(\d+)\s*(ms|sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days|wk|wks|week|weeks|mo|month|months|yr|yrs|year|years|s|m|h|d|w|M|y)$/i,
  );
  if (anchorOffset) {
    const base = parseAnchorKeyword(anchorOffset[1], now);
    if (base) {
      const sign = anchorOffset[2] === "-" ? -1 : 1;
      const shifted = applyRelativeOffset(base, sign, Number(anchorOffset[3]), anchorOffset[4]);
      if (shifted) {
        return { date: shifted, detectedKind: `相对表达式 (${input})`, isLive: false };
      }
    }
  }

  // 4. Local SQL / Slash Date-Time without explicit timezone: `YYYY-MM-DD HH:mm:ss(.SSS)` or `YYYY/MM/DD ...`
  const localSql = input.match(
    /^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[T\s](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?)?$/,
  );
  if (localSql) {
    const y = Number(localSql[1]);
    const m = Number(localSql[2]);
    const d = Number(localSql[3]);
    const H = Number(localSql[4] ?? "0");
    const M = Number(localSql[5] ?? "0");
    const S = Number(localSql[6] ?? "0");
    const frac = (localSql[7] ?? "").padEnd(3, "0").slice(0, 3);
    const ms = Number(frac || "0");
    const dt = new Date(y, m - 1, d, H, M, S, ms);
    if (
      !Number.isNaN(dt.getTime()) &&
      dt.getFullYear() === y &&
      dt.getMonth() === m - 1 &&
      dt.getDate() === d
    ) {
      return {
        date: dt,
        detectedKind: localSql[4] ? "本地日期时间" : "本地日期",
        isLive: false,
      };
    }
  }

  // 5. Fallback to JS Date.parse for ISO 8601 (with Z or +HH:MM), RFC 2822, English date strings
  const ms = Date.parse(input);
  if (!Number.isNaN(ms)) {
    return {
      date: new Date(ms),
      detectedKind: "ISO / RFC 日期字符串",
      isLive: false,
    };
  }

  return null;
}

export function buildTimestampReport(
  parsed: ParsedTimestamp,
  now: Date = new Date(),
  customTimezones: string[] = [],
): TimestampReport {
  const date = parsed.date;
  const ms = date.getTime();
  const sec = Math.floor(ms / 1000);
  const us = parsed.fractionalNanoseconds ? parsed.fractionalNanoseconds / 1000n : BigInt(ms) * 1000n;
  const ns = parsed.fractionalNanoseconds ?? BigInt(ms) * 1_000_000n;

  const year = date.getFullYear();
  const isLeapYear = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  const dayOfYear = getDayOfYear(date);
  const isoWeek = getIsoWeek(date);
  const quarter = Math.floor(date.getMonth() / 3) + 1;
  const relativeLabel = formatRelativeTime(date, now);

  const dayStart = new Date(year, date.getMonth(), date.getDate(), 0, 0, 0, 0);
  const dayEnd = new Date(year, date.getMonth(), date.getDate(), 23, 59, 59, 999);

  const localTzName = Intl.DateTimeFormat().resolvedOptions().timeZone || "Local";

  const entries: TimestampEntry[] = [
    // Unix
    { id: "unix-s", category: "unix", title: "Unix 秒 (Seconds)", value: String(sec), badge: "s" },
    { id: "unix-ms", category: "unix", title: "Unix 毫秒 (Milliseconds)", value: String(ms), badge: "ms" },
    { id: "unix-us", category: "unix", title: "Unix 微秒 (Microseconds)", value: us.toString(), badge: "μs" },
    { id: "unix-ns", category: "unix", title: "Unix 纳秒 (Nanoseconds)", value: ns.toString(), badge: "ns" },
    {
      id: "unix-hex",
      category: "unix",
      title: "Unix 十六进制 (Hex)",
      value: `0x${(sec >>> 0).toString(16)}`,
      badge: "hex",
    },

    // Standard
    { id: "iso-utc", category: "standard", title: "ISO 8601 (UTC)", value: date.toISOString(), badge: "UTC" },
    { id: "iso-local", category: "standard", title: "ISO 8601 (本地时区)", value: formatLocalIso(date), badge: localTzName },
    { id: "local-dt", category: "standard", title: "本地时间 (YYYY-MM-DD HH:mm:ss)", value: formatLocalDateTime(date), badge: "Local" },
    { id: "local-dt-ms", category: "standard", title: "本地精确时间 (含毫秒)", value: formatLocalDateTime(date, true), badge: "ms" },
    { id: "utc-dt", category: "standard", title: "UTC 时间 (YYYY-MM-DD HH:mm:ss)", value: formatUtcDateTime(date), badge: "UTC" },
    { id: "rfc-2822", category: "standard", title: "RFC 2822 / HTTP 日期", value: date.toUTCString(), badge: "RFC" },
    { id: "compact-dt", category: "standard", title: "紧凑格式 (YYYYMMDDHHmmss)", value: formatLocalDateTime(date).replace(/[-:\s]/g, ""), badge: "14位" },

    // Calendar & Boundaries
    { id: "relative", category: "calendar", title: "相对时间", value: relativeLabel, badge: "Rel" },
    {
      id: "calendar-meta",
      category: "calendar",
      title: "日历信息 (ISO 周 / 年内第几天)",
      value: `${isoWeek} · Q${quarter} · 第 ${dayOfYear} 天${isLeapYear ? " (闰年)" : ""}`,
      badge: isoWeek,
    },
    {
      id: "day-start",
      category: "calendar",
      title: "当天 00:00:00 时间戳 (s / ms)",
      value: `${Math.floor(dayStart.getTime() / 1000)}`,
      badge: "Start",
      description: `ms: ${dayStart.getTime()} (${formatLocalDateTime(dayStart)})`,
    },
    {
      id: "day-end",
      category: "calendar",
      title: "当天 23:59:59 时间戳 (s / ms)",
      value: `${Math.floor(dayEnd.getTime() / 1000)}`,
      badge: "End",
      description: `ms: ${dayEnd.getTime()} (${formatLocalDateTime(dayEnd, true)})`,
    },
  ];

  // World Timezones
  const seenZones = new Set<string>();
  const zoneSpecs = [
    ...customTimezones.map((z) => ({ zone: z.trim(), label: z.trim() })).filter((z) => z.zone.length > 0),
    ...DEFAULT_WORLD_TIMEZONES,
  ];
  for (const spec of zoneSpecs) {
    if (seenZones.has(spec.zone)) continue;
    seenZones.add(spec.zone);
    const tz = formatInTimezone(date, spec.zone);
    if (tz.formatted === "Invalid Timezone") continue;
    entries.push({
      id: `tz-${spec.zone}`,
      category: "timezone",
      title: spec.label,
      value: tz.formatted,
      badge: tz.offset,
    });
  }

  // Code Snippets
  entries.push(
    { id: "code-js", category: "code", title: "JavaScript / TypeScript", value: `new Date(${ms})`, badge: "JS" },
    {
      id: "code-py",
      category: "code",
      title: "Python (datetime)",
      value: `datetime.fromtimestamp(${sec}, tz=timezone.utc)`,
      badge: "Py",
    },
    { id: "code-go", category: "code", title: "Go (time.Unix)", value: `time.Unix(${sec}, 0)`, badge: "Go" },
    { id: "code-sql", category: "code", title: "MySQL / PostgreSQL", value: `FROM_UNIXTIME(${sec})`, badge: "SQL" },
  );

  return {
    parsed,
    entries,
    relativeLabel,
    isoWeek,
    dayOfYear,
    quarter,
    isLeapYear,
  };
}
