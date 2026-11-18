import { decodeBase64Strict, decodeHexStrict, decodeJwt, parseUrlQueryParams } from "./codec.ts";
import { analyzeJson } from "./json-tools.ts";
import { parseTimestampInput } from "./timestamp.ts";
import { inspectIdentifier } from "./uuid.ts";

export interface ClipboardDetection {
  kind: "uuid-or-id" | "jwt" | "timestamp" | "json" | "url" | "base64" | "hex" | "color" | "text";
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
  if (/^https?:\/\//i.test(s) || parseUrlQueryParams(s)) {
    return { kind: "url", label: "URL / 链接参数", preview };
  }
  if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$|^rgba?\(|^hsla?\(/i.test(s)) {
    return { kind: "color", label: "颜色值", preview };
  }
  if (decodeBase64Strict(s)) {
    return { kind: "base64", label: "Base64 编码内容", preview };
  }
  if (decodeHexStrict(s)) {
    return { kind: "hex", label: "Hex 十六进制内容", preview };
  }
  return { kind: "text", label: "纯文本", preview };
}
