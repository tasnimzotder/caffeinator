import { showHUD } from "@raycast/api";
import { control, reportError } from "./client";
export default async function Command() {
  try {
    await control({ command: "stop" });
    await showHUD("Session stopped · sleep settings restored");
  } catch (error) {
    await reportError(error);
  }
}
