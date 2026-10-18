import type { CDPSession } from "playwright";

// Derive the wire protocol from the public browser API that owns these definitions.
declare const protocolSend: CDPSession["send"];
declare const protocolListen: CDPSession["addListener"];
export type CommandName = Parameters<CDPSession["send"]>[0];
export type CommandInput<K extends CommandName> = Parameters<typeof protocolSend<K>>[1];
export type CommandResult<K extends CommandName> = Awaited<ReturnType<typeof protocolSend<K>>>;
export type EventName =
  | "Network.requestWillBeSent"
  | "Network.requestWillBeSentExtraInfo"
  | "Network.responseReceived"
  | "Network.responseReceivedExtraInfo"
  | "Network.loadingFinished"
  | "Network.loadingFailed"
  | "Network.requestServedFromCache"
  | "Network.webSocketCreated"
  | "Network.webSocketWillSendHandshakeRequest"
  | "Network.webSocketHandshakeResponseReceived"
  | "Network.webSocketClosed"
  | "Network.webSocketFrameError"
  | "Runtime.consoleAPICalled"
  | "Runtime.exceptionThrown"
  | "Log.entryAdded"
  | "Page.frameNavigated"
  | "Page.navigatedWithinDocument"
  | "Page.lifecycleEvent"
  | "Page.loadEventFired";
export type EventPayload<K extends EventName> = Parameters<
  Parameters<typeof protocolListen<K>>[1]
>[0];
export interface CdpPort {
  send<K extends CommandName>(
    method: K,
    params?: CommandInput<K>,
    timeout?: number,
    signal?: AbortSignal,
  ): Promise<CommandResult<K>>;
  on<K extends EventName>(method: K, listener: (event: EventPayload<K>) => void): () => unknown;
  waitForEvent?<K extends EventName>(
    method: K,
    predicate?: (event: EventPayload<K>) => boolean,
    timeout?: number,
    signal?: AbortSignal,
  ): Promise<EventPayload<K>>;
  close(): unknown;
}

export interface CdpSocket {
  addEventListener<K extends keyof WebSocketEventMap>(
    type: K,
    listener: (event: WebSocketEventMap[K]) => void,
    options?: AddEventListenerOptions,
  ): void;
  send(data: string): void;
  close(): void;
}

export type ChromeChild = Pick<
  import("node:child_process").ChildProcess,
  "exitCode" | "signalCode" | "pid" | "kill"
> &
  Pick<import("node:events").EventEmitter, "once" | "removeListener"> & {
    stdout?: import("node:stream").Readable | null;
    stderr?: import("node:stream").Readable | null;
  };
export interface ChromeRuntime {
  child: ChromeChild | null;
  endpoint: string | null;
  userDataDir: string;
  close(): Promise<void>;
}
export interface LaunchOptions {
  binary?: string;
  env?: NodeJS.ProcessEnv;
  signal?: AbortSignal | undefined;
  spawnImpl?: (
    command: string,
    args: readonly string[],
    options: import("node:child_process").SpawnOptions,
  ) => ChromeChild;
  onRuntime?: (runtime: ChromeRuntime) => unknown;
  gracefulShutdownTimeout?: number;
  forceShutdownTimeout?: number;
}
