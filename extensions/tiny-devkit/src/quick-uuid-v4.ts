import { Clipboard, LaunchProps, getPreferenceValues, showHUD } from "@raycast/api";
import { formatUuidVariants, generateUuidV4 } from "@shared/uuid";

type Format = "standard" | "uppercase" | "compact" | "compactUpper" | "braced" | "urn";

export default async function Command(props: LaunchProps<{ arguments: { count?: string } }>) {
  const prefs = getPreferenceValues<{ uuidDefaultFormat?: Format }>();
  const fmt: Format = prefs.uuidDefaultFormat ?? "standard";
  const count = Math.max(1, Math.min(100, Number.parseInt(props.arguments?.count ?? "1", 10) || 1));

  const values = Array.from({ length: count }, () => formatUuidVariants(generateUuidV4())[fmt]);
  const output = values.join("\n");
  await Clipboard.copy(output);
  await showHUD(count === 1 ? `已复制 UUID v4: ${output}` : `已复制 ${count} 个 UUID v4`);
}
