import { showHUD } from "@raycast/api";
import { control, reportError } from "./client";
export default async function Command() {
  try {
    const status = await control({ command: "toggle" });
    await showHUD(
      status.is_active
        ? "Caffeinator is keeping your Mac awake"
        : "Session stopped · sleep settings restored",
    );
  } catch (error) {
    await reportError(error);
  }
}
