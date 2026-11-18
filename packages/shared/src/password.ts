import { randomBytes } from "node:crypto";

export interface PasswordPresetResult {
  id: string;
  title: string;
  value: string;
  entropyBits: number;
  strengthLabel: string;
  badge: string;
  description: string;
}

const UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const LOWER = "abcdefghijklmnopqrstuvwxyz";
const DIGITS = "0123456789";
const SYMBOLS = "!@#$%^&*()-_=+[]{}|;:,.<>?";
const AMBIGUOUS = /[0O1lI|`'"]/;

// Compact curated high-clarity word list for readable Diceware-style passphrases
const PASSPHRASE_WORDS = [
  "amber", "anchor", "apple", "arctic", "arrow", "atlas", "aurora", "autumn",
  "bamboo", "beacon", "breeze", "bridge", "bronze", "canyon", "cedar", "cipher",
  "cobalt", "comet", "compass", "copper", "coral", "cosmos", "crater", "crystal",
  "delta", "desert", "dragon", "drift", "eclipse", "ember", "emerald", "engine",
  "falcon", "fiber", "fjord", "flame", "forest", "fossil", "frost", "galaxy",
  "garnet", "geyser", "glacier", "granite", "harbor", "harvest", "haven", "helium",
  "horizon", "indigo", "island", "ivory", "jasper", "juniper", "kernel", "kinetic",
  "lagoon", "lantern", "lattice", "laurel", "legend", "lemon", "liberty", "lotus",
  "lunar", "magnet", "maple", "marble", "matrix", "meadow", "mercury", "meteor",
  "mirage", "monarch", "mosaic", "nebula", "nectar", "neutron", "nimbus", "nordic",
  "obsidian", "ocean", "octave", "olive", "omega", "onyx", "opal", "orbit",
  "orchid", "origin", "osprey", "oxygen", "pacific", "palace", "panda", "paradox",
  "pebble", "pelican", "pepper", "phantom", "phoenix", "photon", "pioneer", "planet",
  "plasma", "plateau", "plum", "polar", "portal", "prism", "pulsar", "puzzle",
  "python", "quantum", "quartz", "quasar", "quest", "quiver", "radar", "radiant",
  "rainbow", "ranger", "raven", "reactor", "redwood", "reef", "relic", "ripple",
  "river", "rocket", "ruby", "runway", "saffron", "sage", "sailor", "sapphire",
  "saturn", "scarlet", "sculpt", "sector", "sequoia", "shadow", "shield", "sierra",
  "signal", "silver", "solar", "solstice", "sonic", "spark", "spectra", "sphere",
  "spiral", "spruce", "starlight", "static", "stellar", "stone", "storm", "stream",
  "summit", "sunrise", "sunset", "swift", "symbol", "tango", "tempest", "terra",
  "thistle", "thunder", "tiger", "timber", "titan", "topaz", "torch", "torrent",
  "transit", "treasure", "trident", "tundra", "tunnel", "turbine", "twilight", "typhoon",
  "ultra", "umbra", "unicorn", "unity", "uranium", "valley", "vanguard", "vector",
  "velvet", "vertex", "vessel", "vibrant", "victor", "violet", "vortex", "voyage",
  "walnut", "wander", "warden", "wave", "whisper", "willow", "winter", "wisdom",
  "wizard", "zenith", "zephyr", "zinc", "zodiac", "zone",
];

function randomInt(maxExclusive: number): number {
  if (maxExclusive <= 1) return 0;
  const range = 0x100000000;
  const limit = range - (range % maxExclusive);
  while (true) {
    const val = randomBytes(4).readUInt32BE(0);
    if (val < limit) return val % maxExclusive;
  }
}

export function generateRandomPassword(options: {
  length: number;
  uppercase?: boolean;
  lowercase?: boolean;
  digits?: boolean;
  symbols?: boolean;
  excludeAmbiguous?: boolean;
}): { password: string; entropyBits: number } {
  const pools: string[] = [];
  const filter = (s: string) =>
    options.excludeAmbiguous
      ? Array.from(s)
          .filter((c) => !AMBIGUOUS.test(c))
          .join("")
      : s;

  if (options.uppercase !== false) pools.push(filter(UPPER));
  if (options.lowercase !== false) pools.push(filter(LOWER));
  if (options.digits !== false) pools.push(filter(DIGITS));
  if (options.symbols) pools.push(filter(SYMBOLS));

  const nonEmptyPools = pools.filter((p) => p.length > 0);
  const fullAlphabet = nonEmptyPools.join("") || filter(LOWER + DIGITS);
  const length = Math.max(4, Math.min(256, options.length));

  const chars: string[] = [];
  // Ensure at least one character from each enabled pool when length allows
  for (const pool of nonEmptyPools) {
    if (chars.length < length) {
      chars.push(pool[randomInt(pool.length)]);
    }
  }
  while (chars.length < length) {
    chars.push(fullAlphabet[randomInt(fullAlphabet.length)]);
  }
  // Fisher-Yates shuffle
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    const tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }

  const entropyBits = Math.round(length * Math.log2(fullAlphabet.length));
  return { password: chars.join(""), entropyBits };
}

export function generatePassphrase(wordCount = 5, separator = "-", capitalize = false): {
  passphrase: string;
  entropyBits: number;
} {
  const count = Math.max(2, Math.min(16, wordCount));
  const chosen: string[] = [];
  for (let i = 0; i < count; i++) {
    let w = PASSPHRASE_WORDS[randomInt(PASSPHRASE_WORDS.length)];
    if (capitalize) w = w.charAt(0).toUpperCase() + w.slice(1);
    chosen.push(w);
  }
  return {
    passphrase: chosen.join(separator),
    entropyBits: Math.round(count * Math.log2(PASSPHRASE_WORDS.length)),
  };
}

export function classifyEntropy(bits: number): string {
  if (bits < 45) return "较弱";
  if (bits < 70) return "中等";
  if (bits < 100) return "强";
  return "极强";
}

export function generatePasswordPresets(): PasswordPresetResult[] {
  const pw16 = generateRandomPassword({ length: 16, symbols: true });
  const pw24 = generateRandomPassword({ length: 24, symbols: true });
  const pwNoSym = generateRandomPassword({ length: 20, symbols: false, excludeAmbiguous: true });
  const pw32 = generateRandomPassword({ length: 32, symbols: true });
  const phrase5 = generatePassphrase(5, "-", false);
  const phrase4Cap = generatePassphrase(4, "-", true);
  const pin6 = generateRandomPassword({ length: 6, uppercase: false, lowercase: false, symbols: false, digits: true });
  const apiToken = `sk_live_${randomBytes(24).toString("base64url")}`;
  const hex256 = randomBytes(32).toString("hex");
  const b64Key = randomBytes(32).toString("base64");
  const hex512 = randomBytes(64).toString("hex");

  return [
    {
      id: "pw-16",
      title: "强密码 · 16 位 (含符号)",
      value: pw16.password,
      entropyBits: pw16.entropyBits,
      strengthLabel: classifyEntropy(pw16.entropyBits),
      badge: `${pw16.entropyBits} bit`,
      description: "日常网站与账号注册推荐：大小写 + 数字 + 特殊符号",
    },
    {
      id: "pw-24",
      title: "高强密码 · 24 位 (含符号)",
      value: pw24.password,
      entropyBits: pw24.entropyBits,
      strengthLabel: classifyEntropy(pw24.entropyBits),
      badge: `${pw24.entropyBits} bit`,
      description: "核心后台、云厂商 Root 与敏感系统推荐",
    },
    {
      id: "pw-20-alnum",
      title: "易读密码 · 20 位 (无符号/去易混淆)",
      value: pwNoSym.password,
      entropyBits: pwNoSym.entropyBits,
      strengthLabel: classifyEntropy(pwNoSym.entropyBits),
      badge: `${pwNoSym.entropyBits} bit`,
      description: "排除 0/O/1/l/I 与特殊符号，适合终端或限制符号的系统",
    },
    {
      id: "phrase-5",
      title: "助记词短语 · 5 词 (Diceware)",
      value: phrase5.passphrase,
      entropyBits: phrase5.entropyBits,
      strengthLabel: classifyEntropy(phrase5.entropyBits),
      badge: `${phrase5.entropyBits} bit`,
      description: "易输入易核对的英文单词短语",
    },
    {
      id: "phrase-4-cap",
      title: "助记词短语 · 4 词首字母大写",
      value: phrase4Cap.passphrase,
      entropyBits: phrase4Cap.entropyBits,
      strengthLabel: classifyEntropy(phrase4Cap.entropyBits),
      badge: `${phrase4Cap.entropyBits} bit`,
      description: "满足首字母大写校验规则的短语密码",
    },
    {
      id: "api-token",
      title: "API Token (Base64URL · 192-bit)",
      value: apiToken,
      entropyBits: 192,
      strengthLabel: "极强",
      badge: "192 bit",
      description: "带 sk_live_ 前缀的 URL 安全随机令牌",
    },
    {
      id: "key-256-hex",
      title: "256-bit Hex 密钥 (AES-256 / HMAC)",
      value: hex256,
      entropyBits: 256,
      strengthLabel: "极强",
      badge: "256 bit",
      description: "64 位十六进制密钥，适用于 AES-256 / JWT HMAC",
    },
    {
      id: "key-256-b64",
      title: "256-bit Base64 Secret (JWT / Webhook)",
      value: b64Key,
      entropyBits: 256,
      strengthLabel: "极强",
      badge: "256 bit",
      description: "标准 Base64 编码的 32 字节随机密钥",
    },
    {
      id: "pw-32",
      title: "超强密码 · 32 位全字符集",
      value: pw32.password,
      entropyBits: pw32.entropyBits,
      strengthLabel: classifyEntropy(pw32.entropyBits),
      badge: `${pw32.entropyBits} bit`,
      description: "高安全数据库主密码 / 服务凭证",
    },
    {
      id: "key-512-hex",
      title: "512-bit Hex 密钥 (HS512 / Master Key)",
      value: hex512,
      entropyBits: 512,
      strengthLabel: "极强",
      badge: "512 bit",
      description: "128 位十六进制主密钥",
    },
    {
      id: "pin-6",
      title: "6 位数字 PIN 码",
      value: pin6.password,
      entropyBits: pin6.entropyBits,
      strengthLabel: classifyEntropy(pin6.entropyBits),
      badge: "6 digits",
      description: "加密随机 6 位数字验证码 / PIN",
    },
  ];
}
