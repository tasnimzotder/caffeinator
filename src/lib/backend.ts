import { invoke, isTauri } from "@tauri-apps/api/core";

export const native = isTauri();
export const preview = !native && import.meta.env.DEV;

export async function command<T>(
  name: string,
  args?: Record<string, unknown>,
): Promise<T> {
  if (native) return invoke<T>(name, args);
  if (preview) return (await import("./preview")).previewCommand<T>(name, args);
  throw new Error("Open Caffeinator on your Mac to control sleep settings.");
}

export async function subscribeStatus(
  callback: (status: import("../types").CaffeinateStatus) => void,
) {
  if (native) {
    const { listen } = await import("@tauri-apps/api/event");
    return listen<import("../types").CaffeinateStatus>(
      "caffeinator://status",
      (event) => callback(event.payload),
    );
  }
  if (preview) return (await import("./preview")).subscribe(callback);
  throw new Error("The native app is unavailable.");
}
