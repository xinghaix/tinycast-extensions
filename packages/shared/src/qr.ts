import qrcode from "qrcode-generator";

export type QrErrorCorrection = "L" | "M" | "Q" | "H";

export interface QrRenderResult {
  svg: string;
  rawSvgDataUri: string;
  dataUrl: string;
  markdownImage: string;
  moduleCount: number;
  byteLength: number;
  errorCorrection: QrErrorCorrection;
}

export function generateQrSvg(
  text: string,
  options?: { errorCorrection?: QrErrorCorrection; marginModules?: number; displaySize?: number },
): QrRenderResult {
  const ec: QrErrorCorrection = options?.errorCorrection ?? "M";
  const margin = options?.marginModules ?? 2;
  const displaySize = options?.displaySize ?? 220;

  // Enable UTF-8 encoding for Chinese / Unicode / Emoji QR content
  if (qrcode.stringToBytesFuncs?.["UTF-8"]) {
    qrcode.stringToBytes = qrcode.stringToBytesFuncs["UTF-8"];
  } else {
    qrcode.stringToBytes = (s: string) => Array.from(Buffer.from(s, "utf8"));
  }

  const qr = qrcode(0, ec);
  qr.addData(text);
  qr.make();

  const count = qr.getModuleCount();
  const total = count + margin * 2;
  const scale = 8;
  const size = total * scale;

  const commands: string[] = [];
  for (let r = 0; r < count; r++) {
    for (let c = 0; c < count; c++) {
      if (qr.isDark(r, c)) {
        const x = (c + margin) * scale;
        const y = (r + margin) * scale;
        commands.push(`M${x} ${y}h${scale}v${scale}h-${scale}z`);
      }
    }
  }

  const svg = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">`,
    `<rect width="${size}" height="${size}" rx="${scale * 2}" fill="#FFFFFF"/>`,
    `<path fill="#111827" d="${commands.join("")}"/>`,
    `</svg>`,
  ].join("");

  const b64 = Buffer.from(svg, "utf8").toString("base64");
  const rawSvgDataUri = `data:image/svg+xml;base64,${b64}`;
  const dataUrl = `${rawSvgDataUri}?raycast-width=${displaySize}&raycast-height=${displaySize}`;
  const markdownImage = `![QR Code](${dataUrl})`;

  return {
    svg,
    rawSvgDataUri,
    dataUrl,
    markdownImage,
    moduleCount: count,
    byteLength: Buffer.byteLength(text, "utf8"),
    errorCorrection: ec,
  };
}
