import { loadFederationHostModule } from "./federation-module";
import { observeFederationRoots } from "./federation-observer";

const federationHostMounts = new Map<HTMLElement, { signature: string; unmount: () => void }>();
const federationHostPending = new Map<HTMLElement, string>();

function federationRootSignature(root: HTMLElement) {
  return [
    root.dataset.applicationKey,
    root.dataset.surfaceId,
    root.dataset.hostScope,
    root.dataset.organizationId,
    root.dataset.userId,
    root.dataset.missionId,
    root.dataset.spacecraftId,
    root.dataset.queryParams,
    root.dataset.catalogUrl,
    root.dataset.fallbackHref,
  ].join("\u0000");
}

function connectedFederationRoot(root: HTMLElement) {
  return root.isConnected && document.documentElement.contains(root);
}

function cleanupFederationHostRoots() {
  for (const [root, mounted] of federationHostMounts) {
    if (!connectedFederationRoot(root)) {
      mounted.unmount();
      federationHostMounts.delete(root);
    }
  }

  for (const root of federationHostPending.keys()) {
    if (!connectedFederationRoot(root)) federationHostPending.delete(root);
  }
}

export function bootstrapFederationRoot(root: HTMLElement) {
  cleanupFederationHostRoots();
  const signature = federationRootSignature(root);
  const mounted = federationHostMounts.get(root);
  if (mounted?.signature === signature) return;

  if (mounted) {
    mounted.unmount();
    federationHostMounts.delete(root);
  }

  if (federationHostPending.get(root) === signature) return;
  federationHostPending.set(root, signature);

  loadFederationHostModule()
    .then((hostModule) => {
      if (federationHostPending.get(root) !== signature) return;
      federationHostPending.delete(root);
      if (!connectedFederationRoot(root)) return;

      const mountedHost = hostModule.bootstrapPhoenixHost(root);
      federationHostMounts.set(root, {
        signature,
        unmount: () => mountedHost.unmount(),
      });
    })
    .catch((reason) => {
      if (federationHostPending.get(root) === signature) federationHostPending.delete(root);
      console.error("Cadence federated host failed to load or mount.", reason);
    });
}

function bootFederationHost() {
  cleanupFederationHostRoots();
  for (const root of document.querySelectorAll<HTMLElement>("#cadence-federation-root")) {
    if (!root.closest("[data-host-managed]")) bootstrapFederationRoot(root);
  }
}

document.addEventListener("phx:page-loading-stop", bootFederationHost);
bootFederationHost();

if (document.body) {
  observeFederationRoots(document.body, bootFederationHost);
}
