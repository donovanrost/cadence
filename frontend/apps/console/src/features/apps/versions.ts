import type { App } from "./api.ts";

/**
 * The row's version text (#679). "v2 · v3 available" only when the server says an update exists
 * (`update_available`, worked out by the registry's ordering): the console never compares
 * versions (#191). An app that isn't installed shows the version it would install.
 */
export function versionMeta(
  a: Pick<App, "state" | "version" | "available_version" | "update_available">,
): string | undefined {
  if (a.state === "not_installed") return `v${a.available_version}`;
  if (!a.version) return undefined;
  return a.update_available ? `v${a.version} · v${a.available_version} available` : `v${a.version}`;
}
