export interface JsonAnalysis {
  valid: boolean;
  repaired: boolean;
  error?: string;
  parsed?: unknown;
  pretty2?: string;
  pretty4?: string;
  minified?: string;
  sortedPretty?: string;
  escapedString?: string;
  yaml?: string;
  tsInterface?: string;
  queryString?: string;
  stats?: {
    rootType: string;
    keyCount: number;
    maxDepth: number;
    byteLength: number;
    minifiedLength: number;
  };
}

/**
 * Strip JS-style comments, normalize single-quoted strings, quote unquoted identifier keys,
 * and drop trailing commas without touching characters inside string literals.
 */
export function repairRelaxedJson(raw: string): string {
  const src = raw.trim();
  // If wrapped as an escaped JSON string literal like "\"{\\\"a\\\":1}\""
  if (src.startsWith('"') && src.endsWith('"')) {
    try {
      const inner = JSON.parse(src);
      if (typeof inner === "string" && (inner.trim().startsWith("{") || inner.trim().startsWith("["))) {
        return inner;
      }
    } catch {
      // ignore
    }
  }

  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    const next = src[i + 1];

    // Double-quoted string literal
    if (ch === '"') {
      let j = i + 1;
      while (j < n) {
        if (src[j] === "\\") {
          j += 2;
          continue;
        }
        if (src[j] === '"') {
          j++;
          break;
        }
        j++;
      }
      out += src.slice(i, j);
      i = j;
      continue;
    }

    // Single-quoted string literal -> double-quoted JSON string
    if (ch === "'") {
      let j = i + 1;
      let inner = "";
      while (j < n) {
        if (src[j] === "\\") {
          const esc = src[j + 1];
          if (esc === "'") inner += "'";
          else if (esc === '"') inner += '\\"';
          else if (esc !== undefined) inner += "\\" + esc;
          j += 2;
          continue;
        }
        if (src[j] === "'") {
          j++;
          break;
        }
        if (src[j] === '"') inner += '\\"';
        else inner += src[j];
        j++;
      }
      out += `"${inner}"`;
      i = j;
      continue;
    }

    // Line comment
    if (ch === "/" && next === "/") {
      i += 2;
      while (i < n && src[i] !== "\n") i++;
      continue;
    }

    // Block comment
    if (ch === "/" && next === "*") {
      i += 2;
      while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++;
      i += 2;
      continue;
    }

    // Unquoted object keys after { or ,
    if (/[a-zA-Z_$]/.test(ch)) {
      const prevNonWs = out.trimEnd().slice(-1);
      if (prevNonWs === "{" || prevNonWs === ",") {
        let j = i;
        while (j < n && /[a-zA-Z0-9_$-]/.test(src[j])) j++;
        let k = j;
        while (k < n && /\s/.test(src[k])) k++;
        if (src[k] === ":") {
          out += `"${src.slice(i, j)}"`;
          i = j;
          continue;
        }
      }
    }

    out += ch;
    i++;
  }

  // Remove trailing commas before } or ] outside strings
  let final = "";
  i = 0;
  while (i < out.length) {
    const ch = out[i];
    if (ch === '"') {
      let j = i + 1;
      while (j < out.length) {
        if (out[j] === "\\") {
          j += 2;
          continue;
        }
        if (out[j] === '"') {
          j++;
          break;
        }
        j++;
      }
      final += out.slice(i, j);
      i = j;
      continue;
    }
    if (ch === ",") {
      let j = i + 1;
      while (j < out.length && /\s/.test(out[j])) j++;
      if (out[j] === "}" || out[j] === "]") {
        i++;
        continue;
      }
    }
    final += ch;
    i++;
  }
  return final;
}

export function sortJsonKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortJsonKeys);
  if (value !== null && typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort((a, b) => a.localeCompare(b))) {
      sorted[key] = sortJsonKeys((value as Record<string, unknown>)[key]);
    }
    return sorted;
  }
  return value;
}

function measureJson(value: unknown, depth = 0): { keyCount: number; maxDepth: number } {
  if (Array.isArray(value)) {
    let keyCount = 0;
    let maxDepth = depth + (value.length > 0 ? 1 : 0);
    for (const item of value) {
      const m = measureJson(item, depth + 1);
      keyCount += m.keyCount;
      maxDepth = Math.max(maxDepth, m.maxDepth);
    }
    return { keyCount, maxDepth };
  }
  if (value !== null && typeof value === "object") {
    const entries = Object.values(value as Record<string, unknown>);
    let keyCount = entries.length;
    let maxDepth = depth + (entries.length > 0 ? 1 : 0);
    for (const v of entries) {
      const m = measureJson(v, depth + 1);
      keyCount += m.keyCount;
      maxDepth = Math.max(maxDepth, m.maxDepth);
    }
    return { keyCount, maxDepth };
  }
  return { keyCount: 0, maxDepth: depth };
}

export function jsonToYaml(value: unknown, indent = 0): string {
  const pad = "  ".repeat(indent);
  if (value === null) return "null";
  if (typeof value === "boolean" || typeof value === "number") return String(value);
  if (typeof value === "string") {
    if (value === "" || /[:#\n\r\t{}[\],&*!|>'"%@`]|^\s|\s$/.test(value) || /^(true|false|null|\d+(\.\d+)?)$/i.test(value)) {
      return JSON.stringify(value);
    }
    return value;
  }
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    return value
      .map((item) => {
        if (item !== null && typeof item === "object") {
          const rendered = jsonToYaml(item, indent + 1);
          const firstTrimmed = rendered.replace(/^\s+/, "");
          return `${pad}- ${firstTrimmed}`;
        }
        return `${pad}- ${jsonToYaml(item, indent + 1)}`;
      })
      .join("\n");
  }
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj);
  if (keys.length === 0) return "{}";
  return keys
    .map((k) => {
      const v = obj[k];
      const safeKey = /^[a-zA-Z0-9_-]+$/.test(k) ? k : JSON.stringify(k);
      if (v !== null && typeof v === "object" && ((Array.isArray(v) && v.length > 0) || (!Array.isArray(v) && Object.keys(v).length > 0))) {
        return `${pad}${safeKey}:\n${jsonToYaml(v, indent + 1)}`;
      }
      return `${pad}${safeKey}: ${jsonToYaml(v, indent + 1)}`;
    })
    .join("\n");
}

function toPascal(name: string): string {
  const cleaned = name.replace(/[^a-zA-Z0-9]+/g, " ").trim();
  if (!cleaned) return "Item";
  const out = cleaned
    .split(/\s+/)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join("");
  return /^[0-9]/.test(out) ? `T${out}` : out;
}

export function jsonToTypeScript(value: unknown, rootName = "Root"): string {
  const interfaces: string[] = [];
  const seenNames = new Set<string>();

  function uniqueName(base: string): string {
    let candidate = toPascal(base);
    let idx = 2;
    while (seenNames.has(candidate)) {
      candidate = `${toPascal(base)}${idx++}`;
    }
    seenNames.add(candidate);
    return candidate;
  }

  function inferType(val: unknown, hint: string): string {
    if (val === null) return "null";
    if (Array.isArray(val)) {
      if (val.length === 0) return "unknown[]";
      const elemTypes = Array.from(new Set(val.map((item) => inferType(item, `${hint}Item`))));
      const union = elemTypes.length === 1 ? elemTypes[0] : `(${elemTypes.join(" | ")})`;
      return `${union}[]`;
    }
    if (typeof val === "object") {
      const name = uniqueName(hint);
      const obj = val as Record<string, unknown>;
      const fields = Object.entries(obj).map(([k, v]) => {
        const keyStr = /^[a-zA-Z_$][a-zA-Z0-9_$]*$/.test(k) ? k : JSON.stringify(k);
        return `  ${keyStr}: ${inferType(v, k)};`;
      });
      interfaces.push(`export interface ${name} {\n${fields.join("\n")}\n}`);
      return name;
    }
    return typeof val;
  }

  const rootType = inferType(value, rootName);
  if (interfaces.length === 0) {
    return `export type ${rootName} = ${rootType};`;
  }
  if (!interfaces.some((i) => i.startsWith(`export interface ${rootName} `))) {
    interfaces.push(`export type ${rootName} = ${rootType};`);
  }
  return interfaces.reverse().join("\n\n");
}

function toQueryString(value: unknown): string | undefined {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return undefined;
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (v === undefined) continue;
    params.append(k, typeof v === "object" ? JSON.stringify(v) : String(v));
  }
  return params.toString();
}

export function analyzeJson(raw: string): JsonAnalysis {
  const trimmed = raw.trim();
  if (!trimmed) return { valid: false, repaired: false, error: "输入为空" };

  let parsed: unknown;
  let repaired = false;
  try {
    parsed = JSON.parse(trimmed);
  } catch (strictErr) {
    const candidate = repairRelaxedJson(trimmed);
    try {
      parsed = JSON.parse(candidate);
      repaired = true;
    } catch {
      return {
        valid: false,
        repaired: false,
        error: strictErr instanceof Error ? strictErr.message : String(strictErr),
      };
    }
  }

  const pretty2 = JSON.stringify(parsed, null, 2);
  const pretty4 = JSON.stringify(parsed, null, 4);
  const minified = JSON.stringify(parsed);
  const sortedPretty = JSON.stringify(sortJsonKeys(parsed), null, 2);
  const escapedString = JSON.stringify(minified);
  const yaml = jsonToYaml(parsed);
  const tsInterface = jsonToTypeScript(parsed);
  const queryString = toQueryString(parsed);
  const metrics = measureJson(parsed);
  const rootType = Array.isArray(parsed)
    ? `Array (${parsed.length})`
    : parsed === null
      ? "null"
      : typeof parsed === "object"
        ? `Object (${Object.keys(parsed as object).length} keys)`
        : typeof parsed;

  return {
    valid: true,
    repaired,
    parsed,
    pretty2,
    pretty4,
    minified,
    sortedPretty,
    escapedString,
    yaml,
    tsInterface,
    queryString,
    stats: {
      rootType,
      keyCount: metrics.keyCount,
      maxDepth: metrics.maxDepth,
      byteLength: Buffer.byteLength(trimmed, "utf8"),
      minifiedLength: Buffer.byteLength(minified, "utf8"),
    },
  };
}
