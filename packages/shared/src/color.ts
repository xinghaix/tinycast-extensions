export interface ParsedSimpleColor {
  r: number; // 0..255
  g: number;
  b: number;
  a: number; // 0..1
  hexUpper: string;
  rgbCss: string;
  hslCss: string;
}

export function parseSimpleColor(raw: string): ParsedSimpleColor | null {
  const s = raw.trim();
  if (!s) return null;

  let r = 0;
  let g = 0;
  let b = 0;
  let a = 1;
  let matched = false;

  const hexMatch = s.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/);
  if (hexMatch) {
    const h = hexMatch[1];
    if (h.length === 3 || h.length === 4) {
      r = parseInt(h[0] + h[0], 16);
      g = parseInt(h[1] + h[1], 16);
      b = parseInt(h[2] + h[2], 16);
      if (h.length === 4) a = parseInt(h[3] + h[3], 16) / 255;
    } else {
      r = parseInt(h.slice(0, 2), 16);
      g = parseInt(h.slice(2, 4), 16);
      b = parseInt(h.slice(4, 6), 16);
      if (h.length === 8) a = parseInt(h.slice(6, 8), 16) / 255;
    }
    matched = true;
  }

  if (!matched) {
    const rgbMatch = s.match(/^rgba?\(\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})(?:\s*[,/]\s*([0-9.]+%?))?\s*\)$/i);
    if (rgbMatch) {
      r = Math.min(255, Number(rgbMatch[1]));
      g = Math.min(255, Number(rgbMatch[2]));
      b = Math.min(255, Number(rgbMatch[3]));
      if (rgbMatch[4]) {
        const tok = rgbMatch[4];
        a = tok.endsWith("%") ? Math.min(1, parseFloat(tok) / 100) : Math.min(1, Number(tok));
      }
      matched = true;
    }
  }

  if (!matched) {
    const hslMatch = s.match(/^hsla?\(\s*([0-9.]+)\s*[,\s]\s*([0-9.]+)%\s*[,\s]\s*([0-9.]+)%(?:\s*[,/]\s*([0-9.]+%?))?\s*\)$/i);
    if (hslMatch) {
      const hue = (((Number(hslMatch[1]) % 360) + 360) % 360) / 360;
      const sat = Math.min(100, Number(hslMatch[2])) / 100;
      const lit = Math.min(100, Number(hslMatch[3])) / 100;
      if (hslMatch[4]) {
        const tok = hslMatch[4];
        a = tok.endsWith("%") ? Math.min(1, parseFloat(tok) / 100) : Math.min(1, Number(tok));
      }
      const hue2rgb = (p: number, q: number, t: number) => {
        const nt = t < 0 ? t + 1 : t > 1 ? t - 1 : t;
        if (nt < 1 / 6) return p + (q - p) * 6 * nt;
        if (nt < 1 / 2) return q;
        if (nt < 2 / 3) return p + (q - p) * (2 / 3 - nt) * 6;
        return p;
      };
      const q = lit < 0.5 ? lit * (1 + sat) : lit + sat - lit * sat;
      const p = 2 * lit - q;
      r = Math.round(hue2rgb(p, q, hue + 1 / 3) * 255);
      g = Math.round(hue2rgb(p, q, hue) * 255);
      b = Math.round(hue2rgb(p, q, hue - 1 / 3) * 255);
      matched = true;
    }
  }

  if (!matched) return null;

  const toHex = (n: number) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0").toUpperCase();
  const hasA = a < 0.998;
  const aRounded = Math.round(a * 100) / 100;
  const hexUpper = hasA ? `#${toHex(r)}${toHex(g)}${toHex(b)}${toHex(a * 255)}` : `#${toHex(r)}${toHex(g)}${toHex(b)}`;
  const rgbCss = hasA ? `rgba(${r}, ${g}, ${b}, ${aRounded})` : `rgb(${r}, ${g}, ${b})`;

  // Convert back to HSL for canonical hslCss
  const rf = r / 255;
  const gf = g / 255;
  const bf = b / 255;
  const maxC = Math.max(rf, gf, bf);
  const minC = Math.min(rf, gf, bf);
  const l = (maxC + minC) / 2;
  let h = 0;
  let sat = 0;
  if (maxC !== minC) {
    const d = maxC - minC;
    sat = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
    if (maxC === rf) h = (gf - bf) / d + (gf < bf ? 6 : 0);
    else if (maxC === gf) h = (bf - rf) / d + 2;
    else h = (rf - gf) / d + 4;
    h *= 60;
  }
  const hDeg = Math.round(h);
  const sPct = Math.round(sat * 100);
  const lPct = Math.round(l * 100);
  const hslCss = hasA ? `hsla(${hDeg}, ${sPct}%, ${lPct}%, ${aRounded})` : `hsl(${hDeg}, ${sPct}%, ${lPct}%)`;

  return { r, g, b, a, hexUpper, rgbCss, hslCss };
}
