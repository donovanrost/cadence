/**
 * Host-owned transport boundary for LiveVue's injected Phoenix hook.
 *
 * live_vue exports its implementation .ts files as its type entry point. Those
 * vendor files do not support our indexed/optional strictness. Keep this narrow
 * declaration of the API we consume instead of weakening checks for host code.
 * The upstream use.ts overload returns LiveHook; pushEvent delegates to Phoenix.
 * Reply data crosses the server boundary as unknown and is decoded by the host.
 * Review this declaration when upgrading live_vue or adding another hook API.
 */
export declare function useLiveVue(): {
  pushEvent(
    event: string,
    payload: Record<string, unknown>,
    reply?: (value: unknown) => void,
  ): void;
};
