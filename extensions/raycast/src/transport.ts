import { createConnection } from "node:net";

// One request per connection. Never replay after a request has been sent:
// a lost reply to Toggle must not silently toggle the session back again.
export function request<T>(
  path: string,
  message: unknown,
  timeout = 180000,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const socket = createConnection(path);
    let response = "";
    let finished = false;
    let sent = false;
    const fail = (error: Error) => {
      if (finished) return;
      finished = true;
      socket.destroy();
      reject(
        sent
          ? new Error(
              `${error.message} Check Session Status before retrying; the command may have completed.`,
            )
          : error,
      );
    };
    socket.setEncoding("utf8");
    socket.setTimeout(timeout, () =>
      fail(new Error("Caffeinator did not respond in time.")),
    );
    socket.once("connect", () => {
      sent = true;
      socket.write(`${JSON.stringify(message)}\n`);
    });
    socket.on("data", (chunk) => {
      response += chunk;
      if (response.length > 65536) {
        fail(new Error("Invalid response from Caffeinator."));
        return;
      }
      const newline = response.indexOf("\n");
      if (newline < 0) return;
      try {
        const result = JSON.parse(response.slice(0, newline)) as T;
        finished = true;
        socket.destroy();
        resolve(result);
      } catch {
        fail(new Error("Invalid response from Caffeinator."));
      }
    });
    socket.once("error", fail);
    socket.once("end", () => {
      if (!finished) fail(new Error("Caffeinator closed the connection."));
    });
  });
}
