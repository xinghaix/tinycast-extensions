import { Clipboard, LaunchProps, getPreferenceValues, showHUD } from "@raycast/api";
import { classifyEntropy, generateRandomPassword } from "@shared/password";

export default async function Command(props: LaunchProps<{ arguments: { length?: string } }>) {
  const prefs = getPreferenceValues<{ defaultPasswordLength?: string }>();
  const rawLen = (props.arguments?.length ?? "").trim() || (prefs.defaultPasswordLength ?? "20");
  const length = Math.max(8, Math.min(128, Number.parseInt(rawLen, 10) || 20));

  const { password, entropyBits } = generateRandomPassword({
    length,
    uppercase: true,
    lowercase: true,
    digits: true,
    symbols: true,
  });

  await Clipboard.copy(password, { concealed: true });
  await showHUD(`已隐私复制 ${length} 位强密码 (${entropyBits} bit · ${classifyEntropy(entropyBits)})`);
}
