import { Socket, type Channel } from "phoenix";
import { readonly, ref } from "vue";

export type Connection = "connecting" | "live" | "offline";

/**
 * One Phoenix socket per tab (contract: docs/apogee/api/realtime.md). App.vue starts it after
 * the session bootstrap. A lost socket is reported as `offline`; screens show their data as stale.
 */
const connection = ref<Connection>("connecting");
let socket: Socket | null = null;
const reconnectListeners = new Set<() => void>();
let everOpened = false;

export function startSocket(path: string, csrfToken: string) {
  if (socket) return;
  socket = new Socket(path, { params: { _csrf_token: csrfToken } });
  socket.onOpen(() => {
    connection.value = "live";
    if (everOpened) for (const listener of reconnectListeners) listener();
    everOpened = true;
  });
  socket.onError(() => {
    connection.value = "offline";
  });
  socket.onClose(() => {
    connection.value = "offline";
  });
  socket.connect();
}

export function stopSocket() {
  socket?.disconnect();
  socket = null;
  everOpened = false;
  connection.value = "connecting";
}

export function useConnection() {
  return readonly(connection);
}

/** Called after the socket reconnects: pushes are not replayed, so owners refetch. */
export function onReconnect(listener: () => void): () => void {
  reconnectListeners.add(listener);
  return () => reconnectListeners.delete(listener);
}

type Entry = { channel: Channel; users: number };
const channels = new Map<string, Entry>();

/** Ref-counted shared channel per topic, so several components can listen to one join. */
export function acquireChannel(topic: string): { channel: Channel; release: () => void } {
  if (!socket) throw new Error("acquireChannel() before startSocket()");
  let entry = channels.get(topic);
  if (!entry) {
    const channel = socket.channel(topic, {});
    channel.join();
    entry = { channel, users: 0 };
    channels.set(topic, entry);
  }
  entry.users += 1;
  const held = entry;
  let released = false;
  return {
    channel: held.channel,
    release: () => {
      if (released) return;
      released = true;
      held.users -= 1;
      if (held.users === 0) {
        held.channel.leave();
        channels.delete(topic);
      }
    },
  };
}
