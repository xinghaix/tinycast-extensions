import { decodeBase64Strict, decodeHexStrict, decodeJwt, parseUrlQueryParams } from "./codec.ts";
import { analyzeJson } from "./json-tools.ts";
import { parseTimestampInput } from "./timestamp.ts";
import { inspectIdentifier } from "./uuid.ts";

const CURRENCY_CODES = new Set([
  "CNY", "USD", "HKD", "JPY", "EUR", "GBP", "TWD", "KRW", "SGD", "AUD",
  "CAD", "CHF", "MOP", "THB", "MYR", "VND", "IDR", "PHP", "INR", "RUB",
  "AED", "SAR", "TRY", "BRL", "MXN", "NZD", "SEK", "NOK", "DKK", "PLN",
  "CZK", "HUF", "RON", "ZAR", "ILS", "BTC", "ETH", "USDT", "SOL", "XAU", "XAG",
]);

function isExplicitCurrencyQuery(s: string): boolean {
  if (!s || s.includes("\n") || s.length > 48 || s.startsWith("#")) return false;
  if (/^(?:US\$|HK\$|NT\$|MOP\$|NZ\$|MX\$|[SACR]\$|RM|[$€£¥￥₩฿₹₽₺₫₱₪₴₿])\s*\d[\d,]*(?:\.\d+)?$/.test(s)) {
    return true;
  }
  const clean = s.replace(/,/g, "");
  const suffixMatch = /^\d+(?:\.\d+)?\s*([A-Za-z]{3,4})$/.exec(clean);
  if (suffixMatch && CURRENCY_CODES.has(suffixMatch[1].toUpperCase())) return true;
  const prefixMatch = /^([A-Za-z]{3,4})\s*\d+(?:\.\d+)?$/.exec(clean);
  if (prefixMatch && CURRENCY_CODES.has(prefixMatch[1].toUpperCase())) return true;
  return false;
}

export interface ClipboardDetection {
  kind: "uuid-or-id" | "jwt" | "timestamp" | "json" | "cert" | "curl" | "url" | "cidr" | "base64" | "hex" | "color" | "currency" | "sql" | "text";
  label: string;
  preview: string;
}

export function detectClipboardKind(raw: string): ClipboardDetection {
  const s = raw.trim();
  if (!s) {
    return { kind: "text", label: "空剪贴板", preview: "" };
  }
  const preview = s.length > 60 ? `${s.slice(0, 60)}…` : s;

  if (inspectIdentifier(s)) {
    return { kind: "uuid-or-id", label: "UUID / 唯一标识符", preview };
  }
  if (decodeJwt(s)) {
    return { kind: "jwt", label: "JWT Token", preview };
  }
  if (/^\d{10}(\.\d+)?$|^\d{13}$|^\d{16}$|^\d{19}$|^\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}/.test(s) && parseTimestampInput(s)) {
    return { kind: "timestamp", label: "时间戳 / 日期", preview };
  }
  if ((s.startsWith("{") || s.startsWith("[")) && analyzeJson(s).valid) {
    return { kind: "json", label: "JSON 数据", preview };
  }
  if (
    s.includes("-----BEGIN CERTIFICATE-----") ||
    /^(?:ssh-(?:ed25519|rsa)|ecdsa-sha2-nistp(?:256|384|521)|sk-ssh-ed25519@openssh\.com)\s+[A-Za-z0-9+/=]{16,}/.test(s)
  ) {
    return { kind: "cert", label: "X.509 证书 / SSH 公钥", preview };
  }
  if (/^curl(?:\s|$)/i.test(s)) {
    return { kind: "curl", label: "cURL 请求命令", preview };
  }
  if (/^https?:\/\//i.test(s) || parseUrlQueryParams(s)) {
    return { kind: "url", label: "URL / 链接参数", preview };
  }
  if (/^(?:25[0-5]|2[0-4]\d|1?\d\d?)(?:\.(?:25[0-5]|2[0-4]\d|1?\d\d?)){3}\/(?:3[0-2]|[12]?\d)$/.test(s)) {
    return { kind: "cidr", label: "CIDR 网段", preview };
  }
  if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$|^rgba?\(|^hsla?\(/i.test(s)) {
    return { kind: "color", label: "颜色值", preview };
  }
  if (isExplicitCurrencyQuery(s)) {
    return { kind: "currency", label: "货币金额 / 汇率", preview };
  }
  if (decodeBase64Strict(s)) {
    return { kind: "base64", label: "Base64 编码内容", preview };
  }
  if (decodeHexStrict(s)) {
    return { kind: "hex", label: "Hex 十六进制内容", preview };
  }
  if (
    s.includes("Preparing:") ||
    (/^(?:with|select|insert\s+into|update|delete\s+from|create\s+table|alter\s+table)\b/i.test(s) &&
      /\b(?:from|into|set|values|where|join|table|select)\b/i.test(s))
  ) {
    return { kind: "sql", label: "SQL 语句 / ORM 日志", preview };
  }
  return { kind: "text", label: "纯文本", preview };
}
