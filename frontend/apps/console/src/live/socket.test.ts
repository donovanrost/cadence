import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";

type Hook = () => void;
const sockets: FakeSocket[] = [];
class FakeSocket {
  connected = false;
  open: Hook[] = [];
  error: Hook[] = [];
  close: Hook[] = [];
  constructor() {
    sockets.push(this);
  }
  onOpen(h: Hook) {
    this.open.push(h);
  }
  onError(h: Hook) {
    this.error.push(h);
  }
  onClose(h: Hook) {
    this.close.push(h);
  }
  joined: Hook[] = [];
  channel() {
    return {
      state: "joining",
      leave: () => {},
      join: () => ({
        receive: (status: string, h: Hook) => {
          if (status === "ok") this.joined.push(h);
        },
      }),
    };
  }
  connect() {}
  disconnect() {}
  isConnected() {
    return this.connected;
  }
  emit(kind: "open" | "error" | "close") {
    for (const h of this[kind]) h();
  }
}
vi.mock("phoenix", () => ({ Socket: FakeSocket }));

const { HEAL_MS, acquireChannel, onReconnect, startSocket, stopSocket, useConnection } =
  await import("./socket.ts");

describe("socket connection state (qa 11-13: a stuck 'Live connection lost')", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    sockets.length = 0;
    stopSocket();
    startSocket("/socket", "csrf");
  });
  afterEach(() => {
    stopSocket();
    vi.useRealTimers();
  });

  it("ignores an error from an old transport once the socket is connected again", () => {
    const s = sockets[0];
    if (!s) throw new Error("no socket");
    s.connected = true;
    s.emit("open");
    s.emit("error");
    expect(useConnection().value).toBe("live");
    s.connected = false;
    s.emit("close");
    expect(useConnection().value).toBe("offline");
  });

  it("heals a stale offline on a connected socket, and owners refetch", () => {
    const s = sockets[0];
    if (!s) throw new Error("no socket");
    const refetch = vi.fn();
    onReconnect(refetch);
    s.connected = true;
    s.emit("open");
    s.connected = false;
    s.emit("error");
    expect(useConnection().value).toBe("offline");
    s.connected = true; // back, but no open event reached us
    vi.advanceTimersByTime(HEAL_MS);
    expect(useConnection().value).toBe("live");
    expect(refetch).toHaveBeenCalledOnce();
  });

  it("a joined channel marks the socket live without waiting for the heal", () => {
    const s = sockets[0];
    if (!s) throw new Error("no socket");
    const handle = acquireChannel("mission:m-1");
    expect(useConnection().value).toBe("connecting");
    s.connected = true; // open event lost; the join still succeeds
    for (const h of s.joined) h();
    expect(useConnection().value).toBe("live");
    handle.release();
  });
});
