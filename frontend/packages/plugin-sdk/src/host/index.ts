/** Surface hosting for the console (L9): load approved federated surfaces and give them a bridge. */
export {
  createReleaseAwareRuntime,
  FEDERATED_LOAD_TIMEOUT_MS,
  loadFederatedApplication,
  type FederatedRuntime,
} from "./remote-loader";
export {
  createHttpHostBridge,
  HostBridgeError,
  type BridgeOptions,
  type HttpHostBridge,
} from "./http-host-bridge";
