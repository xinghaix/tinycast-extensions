import { createHash, randomBytes, randomUUID } from "node:crypto";

export type UuidVersion = "v1" | "v3" | "v4" | "v5" | "v6" | "v7" | "v8" | "nil" | "max";
export type IdKind = UuidVersion | "ulid" | "nanoid" | "ksuid" | "objectid";

export type UuidNamespaceKey = "dns" | "url" | "oid" | "x500";

export const UUID_NAMESPACES: Record<UuidNamespaceKey, { label: string; uuid: string }> = {
  dns: { label: "DNS", uuid: "6ba7b810-9dad-11d1-80b4-00c04fd430c8" },
  url: { label: "URL", uuid: "6ba7b811-9dad-11d1-80b4-00c04fd430c8" },
  oid: { label: "OID", uuid: "6ba7b812-9dad-11d1-80b4-00c04fd430c8" },
  x500: { label: "X.500 DN", uuid: "6ba7b814-9dad-11d1-80b4-00c04fd430c8" },
};

export const NIL_UUID = "00000000-0000-0000-0000-000000000000";
export const MAX_UUID = "ffffffff-ffff-ffff-ffff-ffffffffffff";

/** Milliseconds between Gregorian UUID epoch (1582-10-15T00:00:00Z) and Unix epoch (1970-01-01T00:00:00Z). */
const UUID_GREGORIAN_EPOCH_MS = 12219292800000n;

const CROCKFORD32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const NANOID_ALPHABET = "ModuleSymbhasOwnPr-0123456789ABCDEFGHNRVfgctiUvz_KqYTJkLxpZXIjQW";

// Session-scoped state for monotonic v1/v6/v7/ULID/ObjectID generation
let lastGregorianMs = 0n;
let gregorianTicks = 0n;
const sessionClockSeq = ((randomBytes(2).readUInt16BE(0)) & 0x3fff);
const sessionNode = (() => {
  const bytes = randomBytes(6);
  // RFC 9562 Section 6.10: multicast bit (LSB of first octet) MUST be 1 for random node IDs
  bytes[0] = (bytes[0] | 0x01) & 0xff;
  return bytes;
})();

let lastV7Ms = -1;
let v7Counter = 0;

let lastUlidMs = -1;
const lastUlidRand = new Uint8Array(10);

let objectIdCounter = randomBytes(3).readUIntBE(0, 3);
const objectIdProcess = randomBytes(5);

export function bytesToUuid(bytes: Uint8Array): string {
  if (bytes.length !== 16) {
    throw new Error(`UUID requires 16 bytes, got ${bytes.length}`);
  }
  const hex = Buffer.from(bytes).toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

export function parseUuidBytes(input: string): Uint8Array | null {
  let s = input.trim();
  if (s.toLowerCase().startsWith("urn:uuid:")) {
    s = s.slice(9);
  }
  if (s.startsWith("{") && s.endsWith("}")) {
    s = s.slice(1, -1);
  }
  const hyphenated = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  const compact = /^[0-9a-fA-F]{32}$/;
  let hex: string;
  if (hyphenated.test(s)) {
    hex = s.replace(/-/g, "");
  } else if (compact.test(s)) {
    hex = s;
  } else {
    return null;
  }
  return Uint8Array.from(Buffer.from(hex.toLowerCase(), "hex"));
}

export function normalizeUuid(input: string): string | null {
  const bytes = parseUuidBytes(input);
  return bytes ? bytesToUuid(bytes) : null;
}

function nextGregorianTimestamp100ns(timestampMs?: number): bigint {
  const ms = BigInt(timestampMs ?? Date.now());
  if (timestampMs === undefined) {
    if (ms === lastGregorianMs) {
      gregorianTicks = (gregorianTicks + 1n) % 10000n;
    } else {
      lastGregorianMs = ms;
      gregorianTicks = 0n;
    }
    return (ms + UUID_GREGORIAN_EPOCH_MS) * 10000n + gregorianTicks;
  }
  return (ms + UUID_GREGORIAN_EPOCH_MS) * 10000n;
}

/** RFC 9562 UUID v1 (Gregorian time-based). */
export function generateUuidV1(options?: { timestampMs?: number; node?: Uint8Array; clockSeq?: number }): string {
  const ts = nextGregorianTimestamp100ns(options?.timestampMs);
  const timeLow = Number(ts & 0xffffffffn);
  const timeMid = Number((ts >> 32n) & 0xffffn);
  const timeHi = Number((ts >> 48n) & 0x0fffn);
  const clockSeq = (options?.clockSeq ?? sessionClockSeq) & 0x3fff;
  const node = options?.node ?? sessionNode;

  const out = Buffer.alloc(16);
  out.writeUInt32BE(timeLow >>> 0, 0);
  out.writeUInt16BE(timeMid, 4);
  out.writeUInt16BE(0x1000 | timeHi, 6);
  out[8] = 0x80 | ((clockSeq >> 8) & 0x3f);
  out[9] = clockSeq & 0xff;
  Buffer.from(node.subarray(0, 6)).copy(out, 10);
  return bytesToUuid(out);
}

/** RFC 9562 UUID v6 (Reordered Gregorian time-based, sortable). */
export function generateUuidV6(options?: { timestampMs?: number; node?: Uint8Array; clockSeq?: number }): string {
  const ts = nextGregorianTimestamp100ns(options?.timestampMs);
  const timeHigh = Number((ts >> 28n) & 0xffffffffn);
  const timeMid = Number((ts >> 12n) & 0xffffn);
  const timeLow = Number(ts & 0x0fffn);
  const clockSeq = (options?.clockSeq ?? sessionClockSeq) & 0x3fff;
  const node = options?.node ?? sessionNode;

  const out = Buffer.alloc(16);
  out.writeUInt32BE(timeHigh >>> 0, 0);
  out.writeUInt16BE(timeMid, 4);
  out.writeUInt16BE(0x6000 | timeLow, 6);
  out[8] = 0x80 | ((clockSeq >> 8) & 0x3f);
  out[9] = clockSeq & 0xff;
  Buffer.from(node.subarray(0, 6)).copy(out, 10);
  return bytesToUuid(out);
}

function generateNameBasedUuid(version: 3 | 5, name: string, namespaceUuid: string): string {
  const nsBytes = parseUuidBytes(namespaceUuid);
  if (!nsBytes) {
    throw new Error(`Invalid namespace UUID: ${namespaceUuid}`);
  }
  const algo = version === 3 ? "md5" : "sha1";
  const digest = createHash(algo)
    .update(Buffer.from(nsBytes))
    .update(Buffer.from(name, "utf8"))
    .digest()
    .subarray(0, 16);
  digest[6] = (digest[6] & 0x0f) | (version << 4);
  digest[8] = (digest[8] & 0x3f) | 0x80;
  return bytesToUuid(digest);
}

/** RFC 9562 UUID v3 (MD5 namespace-based). */
export function generateUuidV3(name: string, namespaceUuid: string = UUID_NAMESPACES.dns.uuid): string {
  return generateNameBasedUuid(3, name, namespaceUuid);
}

/** RFC 9562 UUID v5 (SHA-1 namespace-based). */
export function generateUuidV5(name: string, namespaceUuid: string = UUID_NAMESPACES.dns.uuid): string {
  return generateNameBasedUuid(5, name, namespaceUuid);
}

/** RFC 9562 UUID v4 (Random). */
export function generateUuidV4(): string {
  return randomUUID();
}

/** RFC 9562 UUID v7 (Unix epoch millisecond time-ordered with monotonic sub-ms rand_a). */
export function generateUuidV7(timestampMs?: number): string {
  let ms = timestampMs ?? Date.now();
  let randA: number;
  if (timestampMs === undefined) {
    if (ms <= lastV7Ms) {
      ms = lastV7Ms;
      v7Counter = (v7Counter + 1) & 0x0fff;
      if (v7Counter === 0) {
        ms += 1;
        lastV7Ms = ms;
      }
      randA = v7Counter;
    } else {
      lastV7Ms = ms;
      v7Counter = randomBytes(2).readUInt16BE(0) & 0x03ff; // Leave headroom for intra-ms bursts
      randA = v7Counter;
    }
  } else {
    randA = randomBytes(2).readUInt16BE(0) & 0x0fff;
  }

  const out = Buffer.alloc(16);
  const tsBig = BigInt(Math.max(0, Math.floor(ms)));
  out[0] = Number((tsBig >> 40n) & 0xffn);
  out[1] = Number((tsBig >> 32n) & 0xffn);
  out[2] = Number((tsBig >> 24n) & 0xffn);
  out[3] = Number((tsBig >> 16n) & 0xffn);
  out[4] = Number((tsBig >> 8n) & 0xffn);
  out[5] = Number(tsBig & 0xffn);

  out[6] = 0x70 | ((randA >> 8) & 0x0f);
  out[7] = randA & 0xff;

  const randB = randomBytes(8);
  randB.copy(out, 8);
  out[8] = (out[8] & 0x3f) | 0x80;
  return bytesToUuid(out);
}

/** RFC 9562 UUID v8 (Custom/experimental: deterministic SHA-256 when seed provided, else random). */
export function generateUuidV8(seed?: string): string {
  const bytes =
    seed !== undefined && seed.length > 0
      ? Buffer.from(createHash("sha256").update(seed, "utf8").digest().subarray(0, 16))
      : randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return bytesToUuid(bytes);
}

/** Generate a Crockford Base32 ULID (26 chars, monotonic within the same millisecond). */
export function generateUlid(timestampMs?: number): string {
  let ms = timestampMs ?? Date.now();
  const rand = new Uint8Array(10);

  if (timestampMs === undefined && ms <= lastUlidMs) {
    ms = lastUlidMs;
    rand.set(lastUlidRand);
    // Increment 80-bit random payload big-endian
    for (let i = 9; i >= 0; i--) {
      if (rand[i] < 255) {
        rand[i] += 1;
        break;
      }
      rand[i] = 0;
    }
  } else {
    randomBytes(10).copy(rand);
  }

  if (timestampMs === undefined) {
    lastUlidMs = ms;
    lastUlidRand.set(rand);
  }

  // Encode 48-bit timestamp into 10 Crockford chars
  let timeChars = "";
  let t = BigInt(Math.max(0, Math.floor(ms)));
  for (let i = 0; i < 10; i++) {
    timeChars = CROCKFORD32[Number(t & 31n)] + timeChars;
    t >>= 5n;
  }

  // Encode 80-bit random into 16 Crockford chars
  let randBits = 0n;
  for (const byte of rand) {
    randBits = (randBits << 8n) | BigInt(byte);
  }
  let randChars = "";
  for (let i = 0; i < 16; i++) {
    randChars = CROCKFORD32[Number(randBits & 31n)] + randChars;
    randBits >>= 5n;
  }

  return timeChars + randChars;
}

/** Generate a URL-safe NanoID using unbiased rejection sampling. */
export function generateNanoId(size = 21, alphabet = NANOID_ALPHABET): string {
  if (size <= 0) return "";
  const mask = (2 << (31 - Math.clz32((alphabet.length - 1) | 1))) - 1;
  const step = Math.ceil((1.6 * mask * size) / alphabet.length);
  let id = "";
  while (id.length < size) {
    const bytes = randomBytes(step);
    for (let i = 0; i < bytes.length && id.length < size; i++) {
      const idx = bytes[i] & mask;
      if (idx < alphabet.length) {
        id += alphabet[idx];
      }
    }
  }
  return id;
}

const KSUID_EPOCH_SEC = 1400000000n;

/** Generate a 27-character Base62 KSUID. */
export function generateKsuid(timestampMs?: number): string {
  const rawSec = BigInt(Math.floor((timestampMs ?? Date.now()) / 1000)) - KSUID_EPOCH_SEC;
  const sec = rawSec > 0n ? rawSec : 0n;
  const payload = randomBytes(16);
  const raw = Buffer.alloc(20);
  raw.writeUInt32BE(Number(sec & 0xffffffffn) >>> 0, 0);
  payload.copy(raw, 4);

  let value = 0n;
  for (const byte of raw) {
    value = (value << 8n) | BigInt(byte);
  }
  let out = "";
  for (let i = 0; i < 27; i++) {
    const rem = value % 62n;
    out = BASE62[Number(rem)] + out;
    value /= 62n;
  }
  return out;
}

/** Generate a 24-hex MongoDB ObjectID. */
export function generateObjectId(timestampMs?: number): string {
  const sec = Math.floor((timestampMs ?? Date.now()) / 1000) >>> 0;
  objectIdCounter = (objectIdCounter + 1) & 0xffffff;
  const buf = Buffer.alloc(12);
  buf.writeUInt32BE(sec, 0);
  objectIdProcess.copy(buf, 4);
  buf.writeUIntBE(objectIdCounter, 9, 3);
  return buf.toString("hex");
}

export interface UuidVariants {
  standard: string;
  uppercase: string;
  compact: string;
  compactUpper: string;
  braced: string;
  urn: string;
  base64: string;
  base64url: string;
  bigInt: string;
  hexBytes: string;
}

export function formatUuidVariants(uuid: string): UuidVariants {
  const bytes = parseUuidBytes(uuid);
  if (!bytes) {
    throw new Error(`Invalid UUID: ${uuid}`);
  }
  const standard = bytesToUuid(bytes);
  const buf = Buffer.from(bytes);
  const compact = buf.toString("hex");
  return {
    standard,
    uppercase: standard.toUpperCase(),
    compact,
    compactUpper: compact.toUpperCase(),
    braced: `{${standard}}`,
    urn: `urn:uuid:${standard}`,
    base64: buf.toString("base64"),
    base64url: buf.toString("base64url"),
    bigInt: BigInt(`0x${compact}`).toString(10),
    hexBytes: Array.from(bytes)
      .map((b) => `0x${b.toString(16).padStart(2, "0")}`)
      .join(", "),
  };
}

export interface InspectedIdentifier {
  kind: "uuid" | "ulid" | "ksuid" | "objectid";
  normalized: string;
  label: string;
  version?: string;
  variant?: string;
  sortable: boolean;
  timestampMs?: number;
  timestampIso?: string;
  nodeHex?: string;
  clockSeq?: number;
  entropyBits: number;
  uuidVariants?: UuidVariants;
}

function decodeGregorianTimeMs(ts100ns: bigint): number {
  return Number(ts100ns / 10000n - UUID_GREGORIAN_EPOCH_MS);
}

export function decodeUlidTimestamp(ulid: string): number | null {
  const upper = ulid.trim().toUpperCase();
  if (!/^[0-9A-HJKMNP-TV-Z]{26}$/.test(upper)) return null;
  // First char must be <= '7' to prevent 48-bit overflow
  if (CROCKFORD32.indexOf(upper[0]) > 7) return null;
  let ts = 0n;
  for (let i = 0; i < 10; i++) {
    const idx = CROCKFORD32.indexOf(upper[i]);
    if (idx < 0) return null;
    ts = (ts << 5n) | BigInt(idx);
  }
  return Number(ts);
}

export function decodeKsuidTimestamp(ksuid: string): number | null {
  const s = ksuid.trim();
  if (!/^[0-9A-Za-z]{27}$/.test(s)) return null;
  let value = 0n;
  for (const ch of s) {
    const idx = BASE62.indexOf(ch);
    if (idx < 0) return null;
    value = value * 62n + BigInt(idx);
  }
  if (value >= 1n << 160n) return null;
  const secOffset = value >> 128n;
  return Number(secOffset + KSUID_EPOCH_SEC) * 1000;
}

export function decodeObjectIdTimestamp(id: string): number | null {
  const s = id.trim().toLowerCase();
  if (!/^[0-9a-f]{24}$/.test(s)) return null;
  const sec = parseInt(s.slice(0, 8), 16);
  return sec * 1000;
}

export function inspectIdentifier(raw: string): InspectedIdentifier | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;

  const uuidBytes = parseUuidBytes(trimmed);
  if (uuidBytes) {
    const normalized = bytesToUuid(uuidBytes);
    const variants = formatUuidVariants(normalized);

    if (normalized === NIL_UUID) {
      return {
        kind: "uuid",
        normalized,
        label: "Nil UUID (全零)",
        version: "Nil (0)",
        variant: "RFC 9562",
        sortable: false,
        entropyBits: 0,
        uuidVariants: variants,
      };
    }
    if (normalized === MAX_UUID) {
      return {
        kind: "uuid",
        normalized,
        label: "Max / Omni UUID (全F)",
        version: "Max (F)",
        variant: "RFC 9562",
        sortable: false,
        entropyBits: 0,
        uuidVariants: variants,
      };
    }

    const ver = (uuidBytes[6] >> 4) & 0x0f;
    const varByte = uuidBytes[8];
    let variant = "Future / Reserved";
    if ((varByte & 0x80) === 0) variant = "NCS Backward Compatibility";
    else if ((varByte & 0xc0) === 0x80) variant = "RFC 4122 / RFC 9562";
    else if ((varByte & 0xe0) === 0xc0) variant = "Microsoft COM/DCOM";

    let timestampMs: number | undefined;
    let nodeHex: string | undefined;
    let clockSeq: number | undefined;
    let entropyBits = 122;

    if (ver === 1) {
      const buf = Buffer.from(uuidBytes);
      const timeLow = BigInt(buf.readUInt32BE(0));
      const timeMid = BigInt(buf.readUInt16BE(4));
      const timeHi = BigInt(buf.readUInt16BE(6) & 0x0fff);
      const ts100ns = (timeHi << 48n) | (timeMid << 32n) | timeLow;
      timestampMs = decodeGregorianTimeMs(ts100ns);
      clockSeq = ((uuidBytes[8] & 0x3f) << 8) | uuidBytes[9];
      nodeHex = Buffer.from(uuidBytes.subarray(10, 16)).toString("hex").match(/.{2}/g)?.join(":");
      entropyBits = 62;
    } else if (ver === 6) {
      const buf = Buffer.from(uuidBytes);
      const timeHigh = BigInt(buf.readUInt32BE(0));
      const timeMid = BigInt(buf.readUInt16BE(4));
      const timeLow = BigInt(buf.readUInt16BE(6) & 0x0fff);
      const ts100ns = (timeHigh << 28n) | (timeMid << 12n) | timeLow;
      timestampMs = decodeGregorianTimeMs(ts100ns);
      clockSeq = ((uuidBytes[8] & 0x3f) << 8) | uuidBytes[9];
      nodeHex = Buffer.from(uuidBytes.subarray(10, 16)).toString("hex").match(/.{2}/g)?.join(":");
      entropyBits = 62;
    } else if (ver === 7) {
      let ts = 0n;
      for (let i = 0; i < 6; i++) ts = (ts << 8n) | BigInt(uuidBytes[i]);
      timestampMs = Number(ts);
      entropyBits = 74;
    } else if (ver === 3 || ver === 5) {
      entropyBits = 0;
    }

    const versionNames: Record<number, string> = {
      1: "v1 · Gregorian Time-Based",
      2: "v2 · DCE Security",
      3: "v3 · Name-Based (MD5)",
      4: "v4 · Random",
      5: "v5 · Name-Based (SHA-1)",
      6: "v6 · Reordered Time-Based (Sortable)",
      7: "v7 · Unix Epoch Time-Ordered (Sortable)",
      8: "v8 · Custom / Experimental",
    };

    return {
      kind: "uuid",
      normalized,
      label: versionNames[ver] ?? `Unknown Version (${ver})`,
      version: `v${ver}`,
      variant,
      sortable: ver === 6 || ver === 7,
      timestampMs,
      timestampIso:
        timestampMs !== undefined && Number.isFinite(timestampMs) ? new Date(timestampMs).toISOString() : undefined,
      nodeHex,
      clockSeq,
      entropyBits,
      uuidVariants: variants,
    };
  }

  const ulidTs = decodeUlidTimestamp(trimmed);
  if (ulidTs !== null) {
    return {
      kind: "ulid",
      normalized: trimmed.toUpperCase(),
      label: "ULID · Crockford Base32 (Sortable)",
      version: "ULID",
      variant: "48-bit ms + 80-bit random",
      sortable: true,
      timestampMs: ulidTs,
      timestampIso: new Date(ulidTs).toISOString(),
      entropyBits: 80,
    };
  }

  const ksuidTs = decodeKsuidTimestamp(trimmed);
  if (ksuidTs !== null) {
    return {
      kind: "ksuid",
      normalized: trimmed,
      label: "KSUID · Base62 (K-Sortable)",
      version: "KSUID",
      variant: "32-bit sec + 128-bit random",
      sortable: true,
      timestampMs: ksuidTs,
      timestampIso: new Date(ksuidTs).toISOString(),
      entropyBits: 128,
    };
  }

  const oidTs = decodeObjectIdTimestamp(trimmed);
  if (oidTs !== null) {
    return {
      kind: "objectid",
      normalized: trimmed.toLowerCase(),
      label: "MongoDB ObjectID · 12-byte Hex",
      version: "ObjectID",
      variant: "32-bit sec + 5B rand + 3B counter",
      sortable: true,
      timestampMs: oidTs,
      timestampIso: new Date(oidTs).toISOString(),
      entropyBits: 64,
    };
  }

  return null;
}

export function generateIdByKind(
  kind: IdKind,
  options?: { name?: string; namespaceUuid?: string; seed?: string; nanoIdLength?: number; timestampMs?: number },
): string {
  switch (kind) {
    case "v1":
      return generateUuidV1({ timestampMs: options?.timestampMs });
    case "v3":
      return generateUuidV3(options?.name || "example.com", options?.namespaceUuid ?? UUID_NAMESPACES.dns.uuid);
    case "v4":
      return generateUuidV4();
    case "v5":
      return generateUuidV5(options?.name || "example.com", options?.namespaceUuid ?? UUID_NAMESPACES.dns.uuid);
    case "v6":
      return generateUuidV6({ timestampMs: options?.timestampMs });
    case "v7":
      return generateUuidV7(options?.timestampMs);
    case "v8":
      return generateUuidV8(options?.seed);
    case "nil":
      return NIL_UUID;
    case "max":
      return MAX_UUID;
    case "ulid":
      return generateUlid(options?.timestampMs);
    case "nanoid":
      return generateNanoId(options?.nanoIdLength ?? 21);
    case "ksuid":
      return generateKsuid(options?.timestampMs);
    case "objectid":
      return generateObjectId(options?.timestampMs);
  }
}
