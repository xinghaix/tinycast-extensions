import { launchDevKitStudio } from "@shared/launch-studio";

export default async function Command() {
  await launchDevKitStudio({ tool: "network" });
}
