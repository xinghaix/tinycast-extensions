import { Clipboard, showHUD, type LaunchProps } from "@raycast/api";
import { cleanPlainText } from "@shared/system-shortcuts";

interface PlainPasteArgs {
  mode?: string;
}

export default async function Command(props: LaunchProps<{ arguments: PlainPasteArgs }>) {
  const raw = await Clipboard.readText();
  if (!raw || raw.length === 0) {
    await showHUD("剪贴板当前无文本内容");
    return;
  }

  const cleaned = cleanPlainText(raw, props.arguments?.mode);
  if (!cleaned) {
    await showHUD("去除格式与空白后内容为空");
    return;
  }

  await Clipboard.copy(cleaned);
  await Clipboard.paste(cleaned);
  await showHUD(`已纯文本粘贴 (${cleaned.length} 字符，已去除富文本样式)`);
}
