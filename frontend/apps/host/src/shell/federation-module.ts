const url = new URL("/assets/application-host/host/host.js", window.location.origin);
if (import.meta.env.DEV) url.searchParams.set("v", Date.now().toString());
let loading: Promise<typeof import("../phoenix-bootstrap")> | undefined;
export function loadFederationHostModule(): Promise<typeof import("../phoenix-bootstrap")> {
  return (loading ??= import(/* @vite-ignore */ url.href).catch((error) => {
    loading = undefined;
    throw error;
  }));
}
