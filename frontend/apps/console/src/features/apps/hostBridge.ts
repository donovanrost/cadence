import type {
  HostActionReceipt,
  HostActionRequest,
  HostBridge,
  HostSessionDescriptor,
} from "@cadence/plugin-sdk";
import { HostBridgeError, type HttpHostBridge } from "@cadence/plugin-sdk/host";

/**
 * L9 bridge for one mounted surface (api: the app-host session pins ONE scope per browser session, so
 * a surface in another tab can take it over). On `host_session_mismatch` the host re-requests its
 * `/host` read to re-pin, rebuilds the bridge and retries once; if that fails too it says so plainly.
 * Every action receipt goes to `onReceipt` (the save-outcome seam).
 */
export const LOST_TEXT = "This page lost its connection to the app. Reload the page to continue.";

export const isMismatch = (e: unknown) =>
  e instanceof HostBridgeError && e.code === "host_session_mismatch";

export type RepinningBridge = Readonly<{
  bridge: HostBridge;
  /** Re-pin now (the tab regained focus); false when the server no longer gives a session. */
  repinNow: () => Promise<boolean>;
  dispose: () => void;
}>;

export function repinningBridge(options: {
  session: HostSessionDescriptor;
  create: (session: HostSessionDescriptor) => HttpHostBridge;
  repin: () => Promise<HostSessionDescriptor | null>;
  navigate: (href: string) => void;
  onReceipt: (actionId: string, receipt: HostActionReceipt) => void;
  onLost: () => void;
}): RepinningBridge {
  let current = options.create(options.session);

  async function repinNow(): Promise<boolean> {
    const session = await options.repin();
    if (!session) return false;
    current.invalidate();
    current = options.create(session);
    return true;
  }

  async function withRepin<T>(op: (b: HttpHostBridge) => Promise<T>): Promise<T> {
    try {
      return await op(current);
    } catch (first) {
      if (!isMismatch(first)) throw first;
      try {
        if (!(await repinNow())) throw first;
        return await op(current);
      } catch {
        options.onLost();
        throw new Error(LOST_TEXT);
      }
    }
  }

  const bridge: HostBridge = {
    navigate: options.navigate,
    query: (request) => withRepin((b) => b.query(request)),
    subscribe: (listener) => current.subscribe(listener),
    async execute<TInput, TResult>(
      request: HostActionRequest<TInput>,
    ): Promise<HostActionReceipt<TResult>> {
      const receipt = await withRepin((b) => b.execute<TInput, TResult>(request));
      options.onReceipt(request.actionId, receipt);
      return receipt;
    },
  };
  return { bridge, repinNow, dispose: () => current.invalidate() };
}
