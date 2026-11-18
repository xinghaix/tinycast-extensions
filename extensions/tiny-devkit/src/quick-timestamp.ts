import { Clipboard, LaunchProps, getPreferenceValues, showHUD } from "@raycast/api";

export default async function Command(props: LaunchProps<{ arguments: { unit?: string } }>) {
  const prefs = getPreferenceValues<{ quickTimestampUnit?: "s" | "ms" | "iso" }>();
  const arg = (props.arguments?.unit ?? "").trim().toLowerCase();
  const unit = arg === "ms" || arg === "s" || arg === "iso" ? arg : prefs.quickTimestampUnit ?? "s";

  const now = new Date();
  let value: string;
  if (unit === "ms") value = String(now.getTime());
  else if (unit === "iso") value = now.toISOString();
  else value = String(Math.floor(now.getTime() / 1000));

  await Clipboard.copy(value);
  await showHUD(`已复制时间戳 (${unit}): ${value}`);
}
