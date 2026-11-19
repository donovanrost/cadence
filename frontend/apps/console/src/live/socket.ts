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

/** How often the reported state is checked against the socket itself (qa 11-13). */
export const HEAL_MS = 5_000;
let heal: ReturnType<typeof setInterval> | null = null;

function markLive() {
  connection.value = "live";
  if (everOpened) for (const listener of reconnectListeners) listener();
  everOpened = true;
}

export function startSocket(path: string, csrfToken: string) {
  if (socket) return;
  const s = new Socket(path, { params: { _csrf_token: csrfToken } });
  socket = s;
  s.onOpen(markLive);
  // An error or close from an old transport can arrive after the socket has already reopened
  // (a server-side channel crash did this on 11-13): only a socket that's really down is offline.
  s.onError(() => {
    if (!s.isConnected()) connection.value = "offline";
  });
  s.onClose(() => {
    if (!s.isConnected()) connection.value = "offline";
  });
  // Self-heal: a stale "offline" on a connected socket goes back to live (and owners refetch,
  // since pushes may have been missed).
  heal = setInterval(() => {
    if (s.isConnected() && connection.value !== "live") markLive();
  }, HEAL_MS);
  s.connect();
}

export function stopSocket() {
  if (heal !== null) clearInterval(heal);
  heal = null;
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

type Entry = { channel: Channel; users: number; joinListeners: Set<() => void> };
const channels = new Map<string, Entry>();

/** Ref-counted shared channel per topic, so several components can listen to one join. */
export type ChannelHandle = {
  channel: Channel;
  /** Runs on every successful (re)join of the shared channel; returns an unregister function. */
  onJoin: (listener: () => void) => () => void;
  joined: () => boolean;
  release: () => void;
};

export function acquireChannel(topic: string): ChannelHandle {
  if (!socket) throw new Error("acquireChannel() before startSocket()");
  let entry = channels.get(topic);
  if (!entry) {
    const channel = socket.channel(topic, {});
    const joinListeners = new Set<() => void>();
    // The join push keeps its receive hooks across rejoins (reconnects), so this fires every time.
    channel.join().receive("ok", () => {
      // A joined channel proves the socket is up, whatever the open/close events said (qa 11-13:
      // 'Live connection lost' shown while every channel had joined).
      if (connection.value !== "live") markLive();
      for (const listener of joinListeners) listener();
    });
    entry = { channel, users: 0, joinListeners };
    channels.set(topic, entry);
  }
  entry.users += 1;
  const held = entry;
  let released = false;
  return {
    channel: held.channel,
    onJoin: (listener) => {
      held.joinListeners.add(listener);
      return () => held.joinListeners.delete(listener);
    },
    joined: () => held.channel.state === "joined",
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
