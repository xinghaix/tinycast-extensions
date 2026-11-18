export interface TextStats {
  chars: number;
  charsNoSpaces: number;
  bytesUtf8: number;
  words: number;
  lines: number;
}

export interface TextTransformItem {
  id: string;
  category: "case" | "line" | "format";
  title: string;
  output: string;
  badge: string;
}

export function splitIdentifierWords(input: string): string[] {
  const normalized = input
    .trim()
    // Insert boundary before uppercase sequences: `camelCase` -> `camel Case`, `HTTPServer` -> `HTTP Server`
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
    .replace(/[_\-./\\:\s]+/g, " ")
    .trim();
  if (!normalized) return [];
  return normalized.split(/\s+/).filter(Boolean);
}

export function toCamelCase(input: string): string {
  const words = splitIdentifierWords(input);
  if (words.length === 0) return "";
  return words
    .map((w, idx) =>
      idx === 0 ? w.toLowerCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase(),
    )
    .join("");
}

export function toPascalCase(input: string): string {
  return splitIdentifierWords(input)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join("");
}

export function toSnakeCase(input: string): string {
  return splitIdentifierWords(input)
    .map((w) => w.toLowerCase())
    .join("_");
}

export function toConstantCase(input: string): string {
  return splitIdentifierWords(input)
    .map((w) => w.toUpperCase())
    .join("_");
}

export function toKebabCase(input: string): string {
  return splitIdentifierWords(input)
    .map((w) => w.toLowerCase())
    .join("-");
}

export function toDotCase(input: string): string {
  return splitIdentifierWords(input)
    .map((w) => w.toLowerCase())
    .join(".");
}

export function toTitleCase(input: string): string {
  const words = splitIdentifierWords(input);
  if (words.length === 0) return "";
  return words.map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(" ");
}

export function toSentenceCase(input: string): string {
  const words = splitIdentifierWords(input);
  if (words.length === 0) return "";
  const joined = words.map((w) => w.toLowerCase()).join(" ");
  return joined.charAt(0).toUpperCase() + joined.slice(1);
}

export function toSlug(input: string): string {
  return input
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function computeTextStats(input: string): TextStats {
  const lines = input.length === 0 ? 0 : input.split(/\r?\n/).length;
  const trimmed = input.trim();
  const words = trimmed ? trimmed.split(/\s+/).length : 0;
  return {
    chars: Array.from(input).length,
    charsNoSpaces: Array.from(input.replace(/\s+/g, "")).length,
    bytesUtf8: Buffer.byteLength(input, "utf8"),
    words,
    lines,
  };
}

export function transformText(input: string): TextTransformItem[] {
  const rawLines = input.split(/\r?\n/);
  const trimmedLines = rawLines.map((l) => l.trim());
  const nonEmptyLines = rawLines.filter((l) => l.trim().length > 0);
  const dedupedLines = Array.from(new Set(rawLines));
  const sortedAsc = [...rawLines].sort((a, b) => a.localeCompare(b));
  const sortedDesc = [...rawLines].sort((a, b) => b.localeCompare(a));
  const reversed = [...rawLines].reverse();
  const numbered = rawLines.map((l, idx) => `${idx + 1}. ${l}`);

  return [
    { id: "camel", category: "case", title: "camelCase", output: toCamelCase(input), badge: "Case" },
    { id: "pascal", category: "case", title: "PascalCase", output: toPascalCase(input), badge: "Case" },
    { id: "snake", category: "case", title: "snake_case", output: toSnakeCase(input), badge: "Case" },
    { id: "constant", category: "case", title: "CONSTANT_CASE", output: toConstantCase(input), badge: "Case" },
    { id: "kebab", category: "case", title: "kebab-case", output: toKebabCase(input), badge: "Case" },
    { id: "dot", category: "case", title: "dot.case", output: toDotCase(input), badge: "Case" },
    { id: "title", category: "case", title: "Title Case", output: toTitleCase(input), badge: "Case" },
    { id: "sentence", category: "case", title: "Sentence case", output: toSentenceCase(input), badge: "Case" },
    { id: "upper", category: "case", title: "UPPERCASE (全大写)", output: input.toUpperCase(), badge: "Case" },
    { id: "lower", category: "case", title: "lowercase (全小写)", output: input.toLowerCase(), badge: "Case" },
    { id: "slug", category: "case", title: "URL Slug", output: toSlug(input), badge: "Slug" },

    { id: "trim-lines", category: "line", title: "去除首尾空格 (Trim Lines)", output: trimmedLines.join("\n"), badge: `${rawLines.length} 行` },
    { id: "drop-empty", category: "line", title: "移除空行 (Remove Blank Lines)", output: nonEmptyLines.join("\n"), badge: `${nonEmptyLines.length} 行` },
    { id: "dedupe", category: "line", title: "行去重 (Deduplicate Lines)", output: dedupedLines.join("\n"), badge: `${dedupedLines.length} 唯一` },
    { id: "sort-asc", category: "line", title: "行升序排序 (Sort A → Z)", output: sortedAsc.join("\n"), badge: "A-Z" },
    { id: "sort-desc", category: "line", title: "行降序排序 (Sort Z → A)", output: sortedDesc.join("\n"), badge: "Z-A" },
    { id: "reverse-lines", category: "line", title: "反转行序 (Reverse Lines)", output: reversed.join("\n"), badge: "Rev" },
    { id: "number-lines", category: "line", title: "添加行号 (1. 2. 3.)", output: numbered.join("\n"), badge: "1..N" },
    { id: "join-comma", category: "format", title: "合并为逗号列表 (a, b, c)", output: nonEmptyLines.map((l) => l.trim()).join(", "), badge: "CSV" },
    { id: "json-array", category: "format", title: "转为 JSON 字符串数组", output: JSON.stringify(nonEmptyLines.map((l) => l.trim()), null, 2), badge: "JSON" },
    { id: "collapse-ws", category: "format", title: "压缩空白为单空格", output: input.replace(/\s+/g, " ").trim(), badge: "Trim" },
  ];
}
