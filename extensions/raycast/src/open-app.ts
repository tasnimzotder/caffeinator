import { control, reportError } from "./client";
import { closeMainWindow } from "@raycast/api";
export default async function Command() {
  try {
    await closeMainWindow();
    await control({ command: "show" });
  } catch (error) {
    await reportError(error);
  }
}
