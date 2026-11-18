import {
  Clipboard,
  Icon,
  MenuBarExtra,
  getPreferenceValues,
  showHUD,
} from "@raycast/api";
import { useEffect, useState } from "react";
import {
  formatUuidVariants,
  generateNanoId,
  generateUlid,
  generateUuidV4,
  generateUuidV7,
} from "@shared/uuid";
import { decodeBase64Strict, decodeJwt } from "@shared/codec";
import { parseSimpleColor } from "@shared/color";
import { parseTimestampInput, formatLocalDateTime } from "@shared/timestamp";
import { detectClipboardKind } from "@shared/clipboard-detect";
import { launchDevKitStudio, type StudioToolId } from "@shared/launch-studio";

type UuidFmt = "standard" | "uppercase" | "compact" | "compactUpper" | "braced" | "urn";

export default function Command() {
  const prefs = getPreferenceValues<{ uuidDefaultFormat?: UuidFmt }>();
  const fmt: UuidFmt = prefs.uuidDefaultFormat ?? "standard";
  const [clipText, setClipText] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    Clipboard.readText()
      .then((text) => {
        if (alive && text) setClipText(text);
      })
      .catch(() => {})
      .finally(() => {
        if (alive) setIsLoading(false);
      });
    return () => {
      alive = false;
    };
  }, []);

  const copyValue = async (value: string, label: string) => {
    await Clipboard.copy(value);
    await showHUD(`已复制 ${label}: ${value}`);
  };

  const openStudio = async (tool: StudioToolId) => {
    await launchDevKitStudio({ tool, closePalette: false });
  };

  const now = new Date();
  const unixSec = String(Math.floor(now.getTime() / 1000));
  const unixMs = String(now.getTime());

  const detected = clipText ? detectClipboardKind(clipText) : null;
  const clipTs = clipText ? parseTimestampInput(clipText, now) : null;
  const clipB64 = clipText ? decodeBase64Strict(clipText) : null;
  const clipJwt = clipText ? decodeJwt(clipText) : null;
  const clipColor = clipText ? parseSimpleColor(clipText) : null;

  return (
    <MenuBarExtra icon={Icon.WrenchScrewdriver} tooltip="Tinycast DevKit 快捷工具箱" isLoading={isLoading}>
      <MenuBarExtra.Section title="UUID / ID 快速生成">
        <MenuBarExtra.Item
          icon={Icon.Fingerprint}
          title="复制 UUID v7 (时序有序)"
          onAction={() => copyValue(formatUuidVariants(generateUuidV7())[fmt], "UUID v7")}
        />
        <MenuBarExtra.Item
          icon={Icon.Fingerprint}
          title="复制 UUID v4 (随机)"
          onAction={() => copyValue(formatUuidVariants(generateUuidV4())[fmt], "UUID v4")}
        />
        <MenuBarExtra.Item
          icon={Icon.Fingerprint}
          title="复制 ULID"
          onAction={() => copyValue(generateUlid(), "ULID")}
        />
        <MenuBarExtra.Item
          icon={Icon.Fingerprint}
          title="复制 NanoID (21位)"
          onAction={() => copyValue(generateNanoId(21), "NanoID")}
        />
      </MenuBarExtra.Section>

      <MenuBarExtra.Section title="当前时间戳">
        <MenuBarExtra.Item
          icon={Icon.Clock}
          title="复制 Unix 秒"
          subtitle={unixSec}
          onAction={() => copyValue(unixSec, "Unix 秒")}
        />
        <MenuBarExtra.Item
          icon={Icon.Clock}
          title="复制 Unix 毫秒"
          subtitle={unixMs}
          onAction={() => copyValue(unixMs, "Unix 毫秒")}
        />
        <MenuBarExtra.Item
          icon={Icon.Calendar}
          title="复制 ISO 8601 UTC"
          subtitle={now.toISOString()}
          onAction={() => copyValue(now.toISOString(), "ISO 8601")}
        />
      </MenuBarExtra.Section>

      {detected && detected.kind !== "text" && (
        <MenuBarExtra.Section title={`剪贴板识别 · ${detected.label}`}>
          {clipTs && !clipTs.isLive && (
            <MenuBarExtra.Item
              icon={Icon.Clock}
              title="复制转换后本地时间"
              subtitle={formatLocalDateTime(clipTs.date)}
              onAction={() => copyValue(formatLocalDateTime(clipTs.date), "本地时间")}
            />
          )}
          {clipB64 && (
            <MenuBarExtra.Item
              icon={Icon.Code}
              title="复制 Base64 解码结果"
              subtitle={clipB64.text.slice(0, 24)}
              onAction={() => copyValue(clipB64.text, "Base64 解码")}
            />
          )}
          {clipJwt && (
            <MenuBarExtra.Item
              icon={Icon.Key}
              title="复制 JWT Payload"
              subtitle={clipJwt.algorithm}
              onAction={() => copyValue(JSON.stringify(clipJwt.payload, null, 2), "JWT Payload")}
            />
          )}
          {clipColor && (
            <>
              <MenuBarExtra.Item
                icon={Icon.EyeDropper}
                title="复制 HEX 色值"
                subtitle={clipColor.hexUpper}
                onAction={() => copyValue(clipColor.hexUpper, "HEX 色值")}
              />
              <MenuBarExtra.Item
                icon={Icon.EyeDropper}
                title="复制 CSS RGB"
                subtitle={clipColor.rgbCss}
                onAction={() => copyValue(clipColor.rgbCss, "CSS RGB")}
              />
              <MenuBarExtra.Item
                icon={Icon.EyeDropper}
                title="复制 CSS HSL"
                subtitle={clipColor.hslCss}
                onAction={() => copyValue(clipColor.hslCss, "CSS HSL")}
              />
            </>
          )}
        </MenuBarExtra.Section>
      )}

      <MenuBarExtra.Section title="打开原生悬浮工作台">
        <MenuBarExtra.Item icon={Icon.Stars} title="剪贴板智能工作台…" onAction={() => openStudio("smart")} />
        <MenuBarExtra.Item icon={Icon.EyeDropper} title="色值转换与屏幕取色…" onAction={() => openStudio("color")} />
        <MenuBarExtra.Item icon={Icon.Fingerprint} title="UUID 与 ID 生成器…" onAction={() => openStudio("uuid")} />
        <MenuBarExtra.Item icon={Icon.Clock} title="时间戳转换…" onAction={() => openStudio("timestamp")} />
        <MenuBarExtra.Item icon={Icon.Hashtag} title="Hash 与文件校验…" onAction={() => openStudio("hash")} />
        <MenuBarExtra.Item icon={Icon.Code} title="算法编解码 & 加解密…" onAction={() => openStudio("codec")} />
        <MenuBarExtra.Item icon={Icon.CodeBlock} title="JSON 格式化与转换…" onAction={() => openStudio("json")} />
        <MenuBarExtra.Item icon={Icon.Key} title="密码与密钥生成器…" onAction={() => openStudio("password")} />
        <MenuBarExtra.Item icon={Icon.Globe} title="本机 IP 与监听端口…" onAction={() => openStudio("network")} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
