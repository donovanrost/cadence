import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {getHooks} from "live_vue"
import liveVueApp from "../vue.ts"
import {createLiveToastHook} from "../../deps/live_toast"

const Hooks = {
  LiveToast: createLiveToastHook()
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...Hooks, ...getHooks(liveVueApp)}
})

liveSocket.connect()

window.liveSocket = liveSocket

const federationHostUrl = new URL(
  "/assets/application-host/host/host.js",
  window.location.origin
)
if (import.meta.env.DEV) federationHostUrl.searchParams.set("v", Date.now().toString())
const federationHostAsset = federationHostUrl.href
let federationHostModuleLoad
const federationHostMounts = new Map()
const federationHostPending = new Map()

function federationRootSignature(root) {
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
    root.dataset.fallbackHref
  ].join("\u0000")
}

function connectedFederationRoot(root) {
  return root.isConnected && document.documentElement.contains(root)
}

function loadFederationHostModule() {
  if (!federationHostModuleLoad) {
    federationHostModuleLoad = import(/* @vite-ignore */ federationHostAsset).catch((reason) => {
      federationHostModuleLoad = undefined
      throw reason
    })
  }

  return federationHostModuleLoad
}

function cleanupFederationHostRoots() {
  for (const [root, mounted] of federationHostMounts) {
    if (!connectedFederationRoot(root)) {
      mounted.unmount()
      federationHostMounts.delete(root)
    }
  }

  for (const root of federationHostPending.keys()) {
    if (!connectedFederationRoot(root)) federationHostPending.delete(root)
  }
}

export function bootstrapFederationRoot(root) {
  cleanupFederationHostRoots()
  const signature = federationRootSignature(root)
  const mounted = federationHostMounts.get(root)
  if (mounted?.signature === signature) return

  if (mounted) {
    mounted.unmount()
    federationHostMounts.delete(root)
  }

  if (federationHostPending.get(root) === signature) return
  federationHostPending.set(root, signature)

  loadFederationHostModule()
    .then((hostModule) => {
      if (federationHostPending.get(root) !== signature) return
      federationHostPending.delete(root)
      if (!connectedFederationRoot(root)) return

      const mountedHost = hostModule.bootstrapPhoenixHost(root)
      federationHostMounts.set(root, {mountedHost, signature, unmount: () => mountedHost.unmount()})
    })
    .catch((reason) => {
      if (federationHostPending.get(root) === signature) federationHostPending.delete(root)
      console.error("Cadence federated host failed to load or mount.", reason)
    })
}

function bootFederationHost() {
  cleanupFederationHostRoots()
  for (const root of document.querySelectorAll("#cadence-federation-root")) {
    bootstrapFederationRoot(root)
  }
}

document.addEventListener("phx:page-loading-stop", bootFederationHost)
bootFederationHost()

if (document.body) {
  new MutationObserver(bootFederationHost).observe(document.body, {
    childList: true,
    subtree: true
  })
}
