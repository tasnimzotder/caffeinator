import { afterEach, expect, test } from "bun:test";
import { createServer, type Server } from "node:net";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "../src/transport";

const resources: { server: Server; dir: string }[] = [];
afterEach(async () => {
  for (const { server, dir } of resources.splice(0)) {
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rm(dir, { recursive: true, force: true });
  }
});
async function fixture(handler: Parameters<typeof createServer>[0]) {
  const dir = await mkdtemp(join(tmpdir(), "caffeinator-transport-"));
  const path = join(dir, "control.sock");
  const server = createServer(handler);
  resources.push({ server, dir });
  await new Promise<void>((resolve) => server.listen(path, resolve));
  return path;
}
test("reads a response split across socket chunks", async () => {
  const path = await fixture((socket) =>
    socket.once("data", () => {
      socket.write('{"ok":');
      setTimeout(() => socket.end("true}\n"), 10);
    }),
  );
  expect(await request(path, { command: "status" }, 1000)).toEqual({
    ok: true,
  });
});
test("does not replay a toggle after a lost response", async () => {
  let received = 0;
  const path = await fixture((socket) =>
    socket.once("data", () => {
      received++;
      socket.end();
    }),
  );
  await expect(request(path, { command: "toggle" }, 1000)).rejects.toThrow(
    "may have completed",
  );
  expect(received).toBe(1);
});
test("rejects malformed JSON responses", async () => {
  const path = await fixture((socket) =>
    socket.once("data", () => socket.end("not json\n")),
  );
  await expect(request(path, { command: "status" }, 1000)).rejects.toThrow(
    "Invalid response",
  );
});
test("bounds response size", async () => {
  const path = await fixture((socket) =>
    socket.once("data", () => socket.end("x".repeat(70000))),
  );
  await expect(request(path, { command: "status" }, 1000)).rejects.toThrow(
    "Invalid response",
  );
});
test("preserves pre-connection errors for safe automatic launch", async () => {
  const dir = await mkdtemp(join(tmpdir(), "caffeinator-missing-"));
  try {
    await expect(
      request(join(dir, "missing.sock"), { command: "status" }, 1000),
    ).rejects.toHaveProperty("code", "ENOENT");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
