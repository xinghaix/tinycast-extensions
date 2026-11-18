import { createCipheriv, createDecipheriv, createHmac, pbkdf2Sync, randomBytes } from "node:crypto";
import { deflateSync, gunzipSync, gzipSync, inflateSync } from "node:zlib";

export type CodecDirection = "encode" | "decode" | "inspect";

export interface CodecEntry {
  id: string;
  title: string;
  direction: CodecDirection;
  category: "base" | "web" | "text" | "compression" | "token" | "radix";
  output: string;
  plausible: boolean;
  badge: string;
  detailsMarkdown?: string;
  metadata?: Array<{ title: string; value: string }>;
}

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

export function encodeBase32(bytes: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let out = "";
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  while (out.length % 8 !== 0) out += "=";
  return out;
}

export function decodeBase32(input: string): Buffer | null {
  const cleaned = input.trim().replace(/\s+/g, "").replace(/=+$/, "").toUpperCase();
  if (!cleaned || !/^[A-Z2-7]+$/.test(cleaned)) return null;
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const ch of cleaned) {
    const idx = BASE32_ALPHABET.indexOf(ch);
    if (idx < 0) return null;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

export function encodeBase58(bytes: Uint8Array): string {
  if (bytes.length === 0) return "";
  let leadingZeros = 0;
  while (leadingZeros < bytes.length && bytes[leadingZeros] === 0) leadingZeros++;
  let num = 0n;
  for (const b of bytes) num = (num << 8n) | BigInt(b);
  let encoded = "";
  while (num > 0n) {
    encoded = BASE58_ALPHABET[Number(num % 58n)] + encoded;
    num /= 58n;
  }
  return "1".repeat(leadingZeros) + encoded;
}

export function decodeBase58(input: string): Buffer | null {
  const s = input.trim();
  if (!s || !/^[1-9A-HJ-NP-Za-km-z]+$/.test(s)) return null;
  let leadingOnes = 0;
  while (leadingOnes < s.length && s[leadingOnes] === "1") leadingOnes++;
  let num = 0n;
  for (const ch of s) {
    const idx = BASE58_ALPHABET.indexOf(ch);
    if (idx < 0) return null;
    num = num * 58n + BigInt(idx);
  }
  const bytes: number[] = [];
  while (num > 0n) {
    bytes.unshift(Number(num & 0xffn));
    num >>= 8n;
  }
  for (let i = 0; i < leadingOnes; i++) bytes.unshift(0);
  return Buffer.from(bytes);
}

const HTML_NAMED_ENCODE: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

const HTML_NAMED_DECODE: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: "\u00a0",
  copy: "©",
  reg: "®",
  trade: "™",
  mdash: "—",
  ndash: "–",
  hellip: "…",
  laquo: "«",
  raquo: "»",
};

export function encodeHtmlEntities(input: string): string {
  return input.replace(/[&<>"']/g, (ch) => HTML_NAMED_ENCODE[ch] ?? ch);
}

export function decodeHtmlEntities(input: string): string {
  return input.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (full, entity: string) => {
    if (entity.startsWith("#x") || entity.startsWith("#X")) {
      const cp = parseInt(entity.slice(2), 16);
      return Number.isFinite(cp) && cp <= 0x10ffff ? String.fromCodePoint(cp) : full;
    }
    if (entity.startsWith("#")) {
      const cp = parseInt(entity.slice(1), 10);
      return Number.isFinite(cp) && cp <= 0x10ffff ? String.fromCodePoint(cp) : full;
    }
    return HTML_NAMED_DECODE[entity] ?? full;
  });
}

export function encodeUnicodeEscapes(input: string, es6 = false): string {
  let out = "";
  for (const ch of input) {
    const cp = ch.codePointAt(0)!;
    if (cp >= 0x20 && cp <= 0x7e) {
      out += ch;
    } else if (es6) {
      out += `\\u{${cp.toString(16)}}`;
    } else if (cp <= 0xffff) {
      out += `\\u${cp.toString(16).padStart(4, "0")}`;
    } else {
      const adj = cp - 0x10000;
      const hi = 0xd800 + (adj >> 10);
      const lo = 0xdc00 + (adj & 0x3ff);
      out += `\\u${hi.toString(16)}\\u${lo.toString(16)}`;
    }
  }
  return out;
}

export function decodeUnicodeEscapes(input: string): string {
  return input
    .replace(/\\u\{([0-9a-fA-F]{1,6})\}/g, (full, hex: string) => {
      const cp = parseInt(hex, 16);
      return cp <= 0x10ffff ? String.fromCodePoint(cp) : full;
    })
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, hex: string) => String.fromCharCode(parseInt(hex, 16)))
    .replace(/\\x([0-9a-fA-F]{2})/g, (_, hex: string) => String.fromCharCode(parseInt(hex, 16)));
}

export function formatCodePoints(input: string): string {
  return Array.from(input)
    .slice(0, 48)
    .map((ch) => `U+${ch.codePointAt(0)!.toString(16).toUpperCase().padStart(4, "0")}`)
    .join(" ");
}

export function rot13(input: string): string {
  return input.replace(/[a-zA-Z]/g, (c) => {
    const base = c <= "Z" ? 65 : 97;
    return String.fromCharCode(((c.charCodeAt(0) - base + 13) % 26) + base);
  });
}

const MORSE_MAP: Record<string, string> = {
  A: ".-", B: "-...", C: "-.-.", D: "-..", E: ".", F: "..-.", G: "--.", H: "....",
  I: "..", J: ".---", K: "-.-", L: ".-..", M: "--", N: "-.", O: "---", P: ".--.",
  Q: "--.-", R: ".-.", S: "...", T: "-", U: "..-", V: "...-", W: ".--", X: "-..-",
  Y: "-.--", Z: "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--",
  "4": "....-", "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
  ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.", "-": "-....-",
  "(": "-.--.", ")": "-.--.-", "@": ".--.-.",
};
const MORSE_REVERSE = Object.fromEntries(Object.entries(MORSE_MAP).map(([k, v]) => [v, k]));

export function encodeMorse(input: string): string {
  return input
    .toUpperCase()
    .split(/\s+/)
    .filter(Boolean)
    .map((word) =>
      Array.from(word)
        .map((ch) => MORSE_MAP[ch] ?? ch)
        .join(" "),
    )
    .join(" / ");
}

export function decodeMorse(input: string): string | null {
  const trimmed = input.trim();
  if (!trimmed || !/^[.\-/\s]+$/.test(trimmed)) return null;
  return trimmed
    .split(/\s*\/\s*/)
    .map((word) =>
      word
        .trim()
        .split(/\s+/)
        .map((code) => MORSE_REVERSE[code] ?? "?")
        .join(""),
    )
    .join(" ");
}

function looksReadableUtf8(buf: Buffer): boolean {
  if (buf.length === 0) return false;
  const decoded = buf.toString("utf8");
  if (decoded.includes("\ufffd")) return false;
  let controlCount = 0;
  for (let i = 0; i < decoded.length; i++) {
    const code = decoded.charCodeAt(i);
    if (code < 0x20 && code !== 9 && code !== 10 && code !== 13) controlCount++;
  }
  return controlCount === 0;
}

export function decodeBase64Strict(input: string): { buffer: Buffer; text: string; isUrlSafe: boolean } | null {
  const s = input.trim().replace(/\s+/g, "");
  if (s.length < 2) return null;
  const isUrlSafe = s.includes("-") || s.includes("_");
  if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(s)) return null;
  const normalized = s.replace(/-/g, "+").replace(/_/g, "/");
  if (normalized.length % 4 === 1) return null;
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const buffer = Buffer.from(padded, "base64");
  if (!looksReadableUtf8(buffer)) return null;
  // Re-encode check prevents false positives on ordinary English words like "hello"
  const reStd = buffer.toString("base64");
  const reNoPad = reStd.replace(/=+$/, "");
  if (padded !== reStd && normalized.replace(/=+$/, "") !== reNoPad) return null;
  return { buffer, text: buffer.toString("utf8"), isUrlSafe };
}

export function decodeHexStrict(input: string): { buffer: Buffer; text: string } | null {
  const cleaned = input.trim().replace(/^0x/i, "").replace(/[\s:-]/g, "");
  if (cleaned.length < 2 || cleaned.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(cleaned)) {
    return null;
  }
  const buffer = Buffer.from(cleaned, "hex");
  if (!looksReadableUtf8(buffer)) return null;
  return { buffer, text: buffer.toString("utf8") };
}

export interface DecodedJwt {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  signatureB64Url: string;
  signingInput: string;
  algorithm: string;
  issuedAt?: string;
  expiresAt?: string;
  notBefore?: string;
  isExpired?: boolean;
}

export function decodeJwt(token: string): DecodedJwt | null {
  const parts = token.trim().split(".");
  if (parts.length !== 3) return null;
  const [hPart, pPart, sPart] = parts;
  if (!hPart || !pPart) return null;
  try {
    const header = JSON.parse(Buffer.from(hPart, "base64url").toString("utf8")) as Record<string, unknown>;
    const payload = JSON.parse(Buffer.from(pPart, "base64url").toString("utf8")) as Record<string, unknown>;
    if (!header || typeof header !== "object" || !payload || typeof payload !== "object") return null;

    const toIso = (val: unknown): string | undefined =>
      typeof val === "number" && Number.isFinite(val) ? new Date(val * 1000).toISOString() : undefined;

    const exp = typeof payload.exp === "number" ? payload.exp : undefined;
    return {
      header,
      payload,
      signatureB64Url: sPart,
      signingInput: `${hPart}.${pPart}`,
      algorithm: String(header.alg ?? "none"),
      issuedAt: toIso(payload.iat),
      expiresAt: toIso(payload.exp),
      notBefore: toIso(payload.nbf),
      isExpired: exp !== undefined ? Date.now() > exp * 1000 : undefined,
    };
  } catch {
    return null;
  }
}

export function verifyJwtHmac(token: string, secret: string): { supported: boolean; valid: boolean; algorithm: string } {
  const decoded = decodeJwt(token);
  if (!decoded) return { supported: false, valid: false, algorithm: "invalid" };
  const algMap: Record<string, string> = { HS256: "sha256", HS384: "sha384", HS512: "sha512" };
  const digest = algMap[decoded.algorithm];
  if (!digest) return { supported: false, valid: false, algorithm: decoded.algorithm };
  const expected = createHmac(digest, secret).update(decoded.signingInput).digest("base64url");
  return { supported: true, valid: expected === decoded.signatureB64Url, algorithm: decoded.algorithm };
}

export function parseUrlQueryParams(input: string): Array<[string, string]> | null {
  const s = input.trim();
  if (!s) return null;
  let query = "";
  if (/^https?:\/\//i.test(s)) {
    try {
      const u = new URL(s);
      query = u.search;
    } catch {
      return null;
    }
  } else if (s.includes("=") && (s.includes("?") || s.includes("&"))) {
    query = s.includes("?") ? s.slice(s.indexOf("?")) : `?${s}`;
  } else {
    return null;
  }
  const params = Array.from(new URLSearchParams(query).entries());
  return params.length > 0 ? params : null;
}

export function parseBigIntRadix(input: string): { value: bigint; sourceRadix: string } | null {
  const s = input.trim().replace(/_/g, "");
  if (!s) return null;
  try {
    if (/^-?0x[0-9a-fA-F]+$/i.test(s)) return { value: BigInt(s), sourceRadix: "Hex (16)" };
    if (/^-?0b[01]+$/i.test(s)) return { value: BigInt(s), sourceRadix: "Binary (2)" };
    if (/^-?0o[0-7]+$/i.test(s)) return { value: BigInt(s), sourceRadix: "Octal (8)" };
    if (/^-?\d+$/.test(s)) return { value: BigInt(s), sourceRadix: "Decimal (10)" };
  } catch {
    return null;
  }
  return null;
}

export function runAllCodecs(input: string): CodecEntry[] {
  const entries: CodecEntry[] = [];
  const buf = Buffer.from(input, "utf8");

  // 1. JWT Inspect (highest signal when input is a JWT)
  const jwt = decodeJwt(input);
  if (jwt) {
    const prettyPayload = JSON.stringify(jwt.payload, null, 2);
    const prettyHeader = JSON.stringify(jwt.header, null, 2);
    const lines = [
      "### Header",
      "```json",
      prettyHeader,
      "```",
      "### Payload",
      "```json",
      prettyPayload,
      "```",
    ];
    const meta: Array<{ title: string; value: string }> = [
      { title: "Algorithm", value: jwt.algorithm },
    ];
    if (jwt.expiresAt) {
      meta.push({ title: "Expires (exp)", value: `${jwt.expiresAt}${jwt.isExpired ? " (已过期)" : " (有效)"}` });
    }
    if (jwt.issuedAt) meta.push({ title: "Issued (iat)", value: jwt.issuedAt });
    if (jwt.notBefore) meta.push({ title: "Not Before (nbf)", value: jwt.notBefore });

    entries.push({
      id: "jwt-decode",
      title: "JWT 解析 (Header & Payload)",
      direction: "inspect",
      category: "token",
      output: prettyPayload,
      plausible: true,
      badge: jwt.isExpired === true ? `${jwt.algorithm} · 已过期` : jwt.algorithm,
      detailsMarkdown: lines.join("\n"),
      metadata: meta,
    });
  }

  // 2. URL Query String Parser
  const qParams = parseUrlQueryParams(input);
  if (qParams) {
    const asJson = JSON.stringify(Object.fromEntries(qParams), null, 2);
    const md = [
      "### URL 参数表",
      "```json",
      asJson,
      "```",
      ...qParams.map(([k, v]) => `- \`${k}\` = \`${v}\``),
    ].join("\n");
    entries.push({
      id: "url-params",
      title: "URL Query 参数解析 (转 JSON)",
      direction: "inspect",
      category: "web",
      output: asJson,
      plausible: true,
      badge: `${qParams.length} 个参数`,
      detailsMarkdown: md,
    });
  }

  // 3. Base64 & Base64URL Decode
  const b64Decoded = decodeBase64Strict(input);
  if (b64Decoded) {
    entries.push({
      id: "base64-decode",
      title: b64Decoded.isUrlSafe ? "Base64URL 解码" : "Base64 解码",
      direction: "decode",
      category: "base",
      output: b64Decoded.text,
      plausible: true,
      badge: "可解码",
    });
  }

  // 4. Hex Decode
  const hexDecoded = decodeHexStrict(input);
  if (hexDecoded) {
    entries.push({
      id: "hex-decode",
      title: "Hex 十六进制解码",
      direction: "decode",
      category: "base",
      output: hexDecoded.text,
      plausible: true,
      badge: "可解码",
    });
  }

  // 5. Base32 Decode
  const b32Decoded = decodeBase32(input);
  if (b32Decoded && looksReadableUtf8(b32Decoded) && input.trim().length >= 8) {
    entries.push({
      id: "base32-decode",
      title: "Base32 解码",
      direction: "decode",
      category: "base",
      output: b32Decoded.toString("utf8"),
      plausible: true,
      badge: "可解码",
    });
  }

  // 6. Base58 Decode
  const b58Decoded = decodeBase58(input);
  if (b58Decoded && looksReadableUtf8(b58Decoded) && input.trim().length >= 4) {
    entries.push({
      id: "base58-decode",
      title: "Base58 解码",
      direction: "decode",
      category: "base",
      output: b58Decoded.toString("utf8"),
      plausible: true,
      badge: "可解码",
    });
  }

  // 7. URL Decode
  if (/%[0-9a-fA-F]{2}/.test(input) || input.includes("+")) {
    try {
      const decoded = decodeURIComponent(input.replace(/\+/g, " "));
      if (decoded !== input) {
        entries.push({
          id: "url-decode",
          title: "URL 解码 (decodeURIComponent)",
          direction: "decode",
          category: "web",
          output: decoded,
          plausible: /%[0-9a-fA-F]{2}/.test(input),
          badge: /%[0-9a-fA-F]{2}/.test(input) ? "可解码" : "URL",
        });
      }
    } catch {
      // Invalid percent sequence
    }
  }

  // 8. HTML Entities Decode
  if (/&(?:#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/.test(input)) {
    const htmlDec = decodeHtmlEntities(input);
    if (htmlDec !== input) {
      entries.push({
        id: "html-decode",
        title: "HTML 实体解码",
        direction: "decode",
        category: "web",
        output: htmlDec,
        plausible: true,
        badge: "可解码",
      });
    }
  }

  // 9. Unicode Escape Decode
  if (/\\u\{?[0-9a-fA-F]{4,6}\}?|\\x[0-9a-fA-F]{2}/.test(input)) {
    const uniDec = decodeUnicodeEscapes(input);
    if (uniDec !== input) {
      entries.push({
        id: "unicode-decode",
        title: "Unicode 转义解码 (\\uXXXX)",
        direction: "decode",
        category: "text",
        output: uniDec,
        plausible: true,
        badge: "可解码",
      });
    }
  }

  // 10. JSON String Unescape
  if ((input.startsWith('"') && input.endsWith('"')) || /\\[nrt"\\]/.test(input)) {
    try {
      const wrapped = input.startsWith('"') && input.endsWith('"') ? input : `"${input}"`;
      const unescaped = String(JSON.parse(wrapped));
      if (unescaped !== input) {
        entries.push({
          id: "json-unescape",
          title: "JSON 字符串反转义",
          direction: "decode",
          category: "text",
          output: unescaped,
          plausible: true,
          badge: "可解码",
        });
      }
    } catch {
      // ignore
    }
  }

  // 11. Gzip / Deflate (Base64) Decompress
  if (/^[A-Za-z0-9+/=_-]{8,}$/.test(input.trim())) {
    try {
      const raw = Buffer.from(input.trim().replace(/-/g, "+").replace(/_/g, "/"), "base64");
      const gunzipped = gunzipSync(raw);
      entries.push({
        id: "gunzip-b64",
        title: "Gzip 解压 (Base64 → UTF-8)",
        direction: "decode",
        category: "compression",
        output: gunzipped.toString("utf8"),
        plausible: true,
        badge: "Gzip",
        metadata: [
          { title: "压缩体积", value: `${raw.length} B` },
          { title: "解压后", value: `${gunzipped.length} B` },
        ],
      });
    } catch {
      // Not gzip
    }
    try {
      const raw = Buffer.from(input.trim().replace(/-/g, "+").replace(/_/g, "/"), "base64");
      const inflated = inflateSync(raw);
      entries.push({
        id: "inflate-b64",
        title: "Deflate 解压 (Base64 → UTF-8)",
        direction: "decode",
        category: "compression",
        output: inflated.toString("utf8"),
        plausible: true,
        badge: "Deflate",
      });
    } catch {
      // Not deflate
    }
  }

  // 12. Binary / Morse Decode
  if (/^[01\s]{8,}$/.test(input.trim())) {
    const bits = input.trim().split(/\s+/);
    if (bits.every((b) => /^[01]{8}$/.test(b))) {
      const binBuf = Buffer.from(bits.map((b) => parseInt(b, 2)));
      if (looksReadableUtf8(binBuf)) {
        entries.push({
          id: "binary-decode",
          title: "二进制 (8-bit) 解码",
          direction: "decode",
          category: "radix",
          output: binBuf.toString("utf8"),
          plausible: true,
          badge: "可解码",
        });
      }
    }
  }
  const morseDec = decodeMorse(input);
  if (morseDec) {
    entries.push({
      id: "morse-decode",
      title: "摩斯电码解码 (Morse)",
      direction: "decode",
      category: "text",
      output: morseDec,
      plausible: true,
      badge: "Morse",
    });
  }

  // 13. Number Radix Conversion (BigInt)
  const radix = parseBigIntRadix(input);
  if (radix) {
    const v = radix.value;
    const sign = v < 0n ? "-" : "";
    const abs = v < 0n ? -v : v;
    const summary = [
      `DEC: ${v.toString(10)}`,
      `HEX: ${sign}0x${abs.toString(16)}`,
      `BIN: ${sign}0b${abs.toString(2)}`,
      `OCT: ${sign}0o${abs.toString(8)}`,
    ].join("\n");
    entries.push(
      {
        id: "radix-hex",
        title: "进制转换 → 十六进制 (Hex)",
        direction: "inspect",
        category: "radix",
        output: `${sign}0x${abs.toString(16)}`,
        plausible: radix.sourceRadix !== "Hex (16)",
        badge: radix.sourceRadix,
        detailsMarkdown: "```\n" + summary + "\n```",
      },
      {
        id: "radix-bin",
        title: "进制转换 → 二进制 (Binary)",
        direction: "inspect",
        category: "radix",
        output: `${sign}0b${abs.toString(2)}`,
        plausible: radix.sourceRadix !== "Binary (2)",
        badge: radix.sourceRadix,
        detailsMarkdown: "```\n" + summary + "\n```",
      },
      {
        id: "radix-dec",
        title: "进制转换 → 十进制 (Decimal)",
        direction: "inspect",
        category: "radix",
        output: v.toString(10),
        plausible: radix.sourceRadix !== "Decimal (10)",
        badge: radix.sourceRadix,
        detailsMarkdown: "```\n" + summary + "\n```",
      },
    );
  }

  // ─── Standard Encodings ────────────────────────────────────────────────────
  const gz = gzipSync(buf);
  const defl = deflateSync(buf);

  entries.push(
    {
      id: "base64-encode",
      title: "Base64 编码",
      direction: "encode",
      category: "base",
      output: buf.toString("base64"),
      plausible: false,
      badge: "Base64",
    },
    {
      id: "base64url-encode",
      title: "Base64URL 编码 (URL 安全无填充)",
      direction: "encode",
      category: "base",
      output: buf.toString("base64url"),
      plausible: false,
      badge: "Base64URL",
    },
    {
      id: "hex-encode",
      title: "Hex 十六进制编码",
      direction: "encode",
      category: "base",
      output: buf.toString("hex"),
      plausible: false,
      badge: "Hex",
      metadata: [
        { title: "空格分隔", value: buf.toString("hex").match(/.{2}/g)?.join(" ") ?? "" },
        { title: "字节长度", value: `${buf.length} bytes` },
      ],
    },
    {
      id: "base32-encode",
      title: "Base32 编码 (RFC 4648)",
      direction: "encode",
      category: "base",
      output: encodeBase32(buf),
      plausible: false,
      badge: "Base32",
    },
    {
      id: "base58-encode",
      title: "Base58 编码 (Bitcoin/IPFS)",
      direction: "encode",
      category: "base",
      output: encodeBase58(buf),
      plausible: false,
      badge: "Base58",
    },
    {
      id: "url-encode-component",
      title: "URL 编码 (encodeURIComponent)",
      direction: "encode",
      category: "web",
      output: encodeURIComponent(input),
      plausible: false,
      badge: "URL",
    },
    {
      id: "url-encode-full",
      title: "完整 URI 编码 (encodeURI)",
      direction: "encode",
      category: "web",
      output: encodeURI(input),
      plausible: false,
      badge: "URI",
    },
    {
      id: "html-encode",
      title: "HTML 实体编码",
      direction: "encode",
      category: "web",
      output: encodeHtmlEntities(input),
      plausible: false,
      badge: "HTML",
    },
    {
      id: "unicode-encode",
      title: "Unicode 转义编码 (\\uXXXX)",
      direction: "encode",
      category: "text",
      output: encodeUnicodeEscapes(input, false),
      plausible: false,
      badge: "Unicode",
      metadata: [{ title: "码点列表", value: formatCodePoints(input) }],
    },
    {
      id: "json-escape",
      title: "JSON 字符串转义",
      direction: "encode",
      category: "text",
      output: JSON.stringify(input),
      plausible: false,
      badge: "JSON",
    },
    {
      id: "gzip-b64",
      title: "Gzip 压缩 → Base64",
      direction: "encode",
      category: "compression",
      output: gz.toString("base64"),
      plausible: false,
      badge: `${buf.length}B → ${gz.length}B`,
    },
    {
      id: "deflate-b64",
      title: "Deflate 压缩 → Base64",
      direction: "encode",
      category: "compression",
      output: defl.toString("base64"),
      plausible: false,
      badge: `${buf.length}B → ${defl.length}B`,
    },
    {
      id: "binary-encode",
      title: "二进制字节序列 (8-bit Binary)",
      direction: "encode",
      category: "radix",
      output: Array.from(buf).map((b) => b.toString(2).padStart(8, "0")).join(" "),
      plausible: false,
      badge: "Bin",
    },
    {
      id: "rot13",
      title: "ROT13 替换密码",
      direction: "encode",
      category: "text",
      output: rot13(input),
      plausible: false,
      badge: "ROT13",
    },
    {
      id: "morse-encode",
      title: "摩斯电码编码 (Morse)",
      direction: "encode",
      category: "text",
      output: encodeMorse(input),
      plausible: false,
      badge: "Morse",
    },
  );

  return entries;
}

// ─── AES-256-GCM / AES-256-CBC (Backed by Tinycast Swift CryptoKit/CommonCrypto) ─

export type AesMode = "aes-256-gcm" | "aes-256-cbc";
export type AesKeyDerivation = "pbkdf2" | "hex" | "utf8-pad";

function deriveAes256Key(keyInput: string, salt: Buffer, derivation: AesKeyDerivation): Buffer {
  if (derivation === "hex") {
    const cleaned = keyInput.replace(/[\s:-]/g, "").replace(/^0x/i, "");
    const buf = Buffer.from(cleaned, "hex");
    if (buf.length !== 32) {
      throw new Error(`Hex 密钥须为 64 个十六进制字符 (32 字节)，当前为 ${buf.length} 字节`);
    }
    return buf;
  }
  if (derivation === "utf8-pad") {
    const out = Buffer.alloc(32);
    Buffer.from(keyInput, "utf8").copy(out, 0, 0, Math.min(32, Buffer.byteLength(keyInput)));
    return out;
  }
  return pbkdf2Sync(Buffer.from(keyInput, "utf8"), salt, 100_000, 32, "sha256");
}

export function encryptAes(
  plaintext: string,
  secret: string,
  mode: AesMode = "aes-256-gcm",
  derivation: AesKeyDerivation = "pbkdf2",
): string {
  if (!secret) throw new Error("请输入密钥或口令");
  const salt = derivation === "pbkdf2" ? randomBytes(16) : Buffer.alloc(0);
  const key = deriveAes256Key(secret, salt, derivation);

  if (mode === "aes-256-gcm") {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", key, iv);
    const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return JSON.stringify({
      v: 1,
      alg: "AES-256-GCM",
      kdf: derivation,
      ...(salt.length ? { salt: salt.toString("base64") } : {}),
      iv: iv.toString("base64"),
      tag: tag.toString("base64"),
      ct: ciphertext.toString("base64"),
    });
  }

  const iv = randomBytes(16);
  const cipher = createCipheriv("aes-256-cbc", key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return JSON.stringify({
    v: 1,
    alg: "AES-256-CBC",
    kdf: derivation,
    ...(salt.length ? { salt: salt.toString("base64") } : {}),
    iv: iv.toString("base64"),
    ct: ciphertext.toString("base64"),
  });
}

export function decryptAes(
  payloadText: string,
  secret: string,
  fallbackMode: AesMode = "aes-256-gcm",
  fallbackDerivation: AesKeyDerivation = "pbkdf2",
): string {
  if (!secret) throw new Error("请输入密钥或口令");
  let parsed: {
    alg?: string;
    kdf?: AesKeyDerivation;
    salt?: string;
    iv: string;
    tag?: string;
    ct: string;
  };
  try {
    parsed = JSON.parse(payloadText.trim());
  } catch {
    throw new Error("密文格式须为加密输出的 JSON Payload");
  }
  const derivation = parsed.kdf ?? fallbackDerivation;
  const salt = parsed.salt ? Buffer.from(parsed.salt, "base64") : Buffer.alloc(0);
  const key = deriveAes256Key(secret, salt, derivation);
  const iv = Buffer.from(parsed.iv, "base64");
  const ct = Buffer.from(parsed.ct, "base64");
  const mode: AesMode =
    parsed.alg === "AES-256-CBC" ? "aes-256-cbc" : parsed.alg === "AES-256-GCM" ? "aes-256-gcm" : fallbackMode;

  if (mode === "aes-256-gcm") {
    if (!parsed.tag) throw new Error("GCM 解密缺少认证 tag");
    const decipher = createDecipheriv("aes-256-gcm", key, iv);
    decipher.setAuthTag(Buffer.from(parsed.tag, "base64"));
    return Buffer.concat([decipher.update(ct), decipher.final()]).toString("utf8");
  }

  const decipher = createDecipheriv("aes-256-cbc", key, iv);
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString("utf8");
}
