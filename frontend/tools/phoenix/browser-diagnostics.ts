import type { EventPayload } from "./cdp-contract";

export type RequestData = Partial<EventPayload<"Network.requestWillBeSent">["request"]>;
export type ResponseData = Partial<EventPayload<"Network.responseReceived">["response"]> & {
  fromMemoryCache?: boolean;
};
export type RequestExtra = Partial<
  Pick<EventPayload<"Network.requestWillBeSentExtraInfo">, "headers" | "associatedCookies">
>;
export type ResponseExtra = Partial<
  Pick<
    EventPayload<"Network.responseReceivedExtraInfo">,
    "headers" | "blockedCookies" | "statusCode"
  >
>;
type Observed<T> = { [K in keyof T]?: T[K] | undefined };
export type CanonicalEntry = Observed<EventPayload<"Log.entryAdded">["entry"]>;
export interface Generation {
  id: number;
  label: string;
  requestSequence: number;
  requestIds: Set<string>;
  startedAtMs: number;
  causalRequestId: string | undefined;
  causalRequestSequence: number | undefined;
}
export interface GenerationState extends Generation {
  public: Generation;
}
export type GenerationSelection = number | Generation | null | undefined;
export interface StatusEvidence {
  source: string;
  status: number;
}
export interface RequestIdentity {
  requestId: string;
  generation?: number | undefined;
  sequence?: number | undefined;
}
export interface RequestObservation extends RequestIdentity {
  sequence: number;
  startedAtMs: number;
  method: string;
  url: string;
  request: RequestData;
  postData?: string | undefined;
  frameId?: string | undefined;
  loaderId?: string | undefined;
  response?: ResponseData | undefined;
  responseExtra?: ResponseExtra | undefined;
  requestExtra?: RequestExtra | undefined;
  statusEvidence: readonly StatusEvidence[];
  statusDisagreement?: string | undefined;
  statusDisagreementReported?: boolean | undefined;
  servedFromCache?: boolean | undefined;
  resourceType?: string | undefined;
  redirects: readonly { status: number; url: string }[];
  webSocket: boolean;
  finished: boolean;
  failed?: string | undefined;
  dataUrl: boolean;
  pendingExpectedFailureLog?: { entry: CanonicalEntry; status: number } | undefined;
  expectedFailureRegistration?: object | undefined;
  expectedFailureAllowance?: Partial<AllowanceObservation> | undefined;
  finalizedExpectedFailure?: Partial<AllowanceObservation> | undefined;
}
export interface AllowanceObservation extends RequestIdentity {
  url: string;
  method: string;
  status: number;
  consumed: boolean;
  consumedEntries: readonly CanonicalEntry[];
  suppressedFailures: readonly string[];
  revoked?: boolean | undefined;
  finalized?: boolean | undefined;
  replayed: boolean;
  record: object;
}
export interface RequestState extends Omit<
  RequestObservation,
  | "pendingExpectedFailureLog"
  | "expectedFailureRegistration"
  | "expectedFailureAllowance"
  | "finalizedExpectedFailure"
> {
  view?: RequestObservation | undefined;
  viewDigest?: string | undefined;
  observationTampered?: string | undefined;
  statusEvidenceView?: unknown;
  pendingExpectedFailureLogView?: unknown;
  responseStatus?: number | undefined;
  responseExtraStatus?: number | undefined;
  pendingExpectedFailureLog?:
    | { entry: CanonicalEntry; status: number; registration: FailureRegistration }
    | undefined;
  expectedFailureRegistration?: FailureRegistration | undefined;
  expectedFailureAllowance?: FailureAllowance | undefined;
  finalizedExpectedFailure?: FailureAllowance | undefined;
}
export interface FailureRegistration {
  predicate: (record: RequestObservation) => boolean;
  expectedStatus: number;
  registeredAfterSequence: number;
  active: boolean;
  allowances: Set<FailureAllowance>;
  view: object;
  requestId?: string | undefined;
  pendingRequestId?: string | undefined;
  invalidated?: boolean;
  finalized?: boolean;
  invalidatedBy?: string;
}
export interface FailureAllowance extends Omit<AllowanceObservation, "record"> {
  registration: FailureRegistration;
  record: RequestState;
  view: Partial<AllowanceObservation>;
  consumedEntriesView?: readonly CanonicalEntry[];
  suppressedFailuresView?: readonly string[];
  invalidatedBy?: string;
}
export interface SocketObservation extends RequestIdentity {
  url: string | undefined;
  boundToRequest: boolean;
  boundByHandshake?: boolean | undefined;
  observedGeneration: number | undefined;
  observedSequence: number;
  causalRequestId?: string | undefined;
  handshakeRequest?:
    | Partial<EventPayload<"Network.webSocketWillSendHandshakeRequest">["request"]>
    | undefined;
  handshake?:
    | Partial<EventPayload<"Network.webSocketHandshakeResponseReceived">["response"]>
    | undefined;
  closed?: boolean | undefined;
  error?: string | undefined;
}

// Standalone assertions also accept deliberately incomplete protocol observations.
export type RequestEvidence = Pick<RequestObservation, "requestId" | "url"> &
  Partial<RequestObservation>;
export interface HeaderEvidence {
  request?: { headers?: unknown } | undefined;
  requestExtra?: { headers?: unknown } | undefined;
  response?: { headers?: unknown } | undefined;
  responseExtra?: { headers?: unknown } | undefined;
}
export interface DetachedDiagnostics {
  webSockets: ReadonlyMap<
    string,
    Omit<SocketObservation, "observedGeneration"> & { observedGeneration?: number | undefined }
  >;
  requests: ReadonlyMap<string, RequestEvidence>;
  webSocketFailures: readonly string[];
  consoleErrors?: readonly string[];
  logErrors?: readonly string[];
}
export interface ReleaseIdentity {
  applicationKey: string;
  releaseId: string;
}
export interface HttpExpectation {
  origin: string;
  method: string;
  pathname: string;
  label: string;
  body?: unknown;
  headers?: Readonly<Record<string, string>>;
  responseHeaders?: Readonly<Record<string, string>>;
  requireIdempotencyKey?: boolean;
}
export interface ReleaseLocation {
  applicationKey?: string | undefined;
  releaseId?: string | undefined;
  artifactPath?: string;
  label?: string;
}
export interface ManifestExpectation extends ReleaseLocation {
  origin?: string | undefined;
  requiredExposedModule?: string | undefined;
  requireImmutableCache?: boolean;
}
export type NavigationResult = { frameId: string; loaderId: string };
export type FrameEvent = {
  kind: "frame";
  params: EventPayload<"Page.frameNavigated">;
  sequence: number;
};
export type LifecycleEvent = {
  kind: "lifecycle";
  params: EventPayload<"Page.lifecycleEvent">;
  sequence: number;
};
export interface NavigationCompletion {
  result: NavigationResult;
  frame: EventPayload<"Page.frameNavigated">["frame"];
  load: EventPayload<"Page.lifecycleEvent">;
}

export type SerializableResult =
  | null
  | string
  | boolean
  | number
  | SerializableResult[]
  | { [key: string]: SerializableResult };
export type SafeCallable = (...parameters: unknown[]) => unknown;
export interface BrowserOwnership {
  runtime: unknown;
  runtimeClose: SafeCallable | null;
  runtimeEndpoint: unknown;
  client: unknown;
  clientClose: SafeCallable | null;
  page: unknown;
  pageId: string | undefined;
  pageEndpoint: unknown;
}
export interface LoginSecret {
  password: string;
}
export interface ScenarioOptions {
  secret: LoginSecret | null;
  signal: AbortSignal;
}
export interface GateOptions {
  env?: NodeJS.ProcessEnv;
  launchChromeImpl?: (
    options: Omit<import("./cdp-contract").LaunchOptions, "onRuntime"> & {
      onRuntime?: (runtime: unknown) => unknown;
    },
  ) => unknown;
  createPageImpl?: (endpoint: string, url: string, options: { signal: AbortSignal }) => unknown;
  closePageImpl?: (endpoint: string, targetId: string, options: { timeout: number }) => unknown;
  createClientImpl?: (endpoint: string) => unknown;
  runScenarioImpl?: (
    client: import("./cdp-contract").CdpPort,
    diagnostics: ReturnType<typeof import("./federation_browser_smoke.mjs").installDiagnostics>,
    args: string[],
    options: ScenarioOptions,
  ) => unknown;
  originUrl?: string;
  clientCreationTimeout?: number;
}

export type ApplicationKey =
  | "comms"
  | "telemetry_decom"
  | "mission_catalog"
  | "ops_console"
  | "organization_admin"
  | "spacecraft";
export interface SurfaceOptions {
  client: import("./cdp-contract").CdpPort;
  diagnostics: ReturnType<typeof import("./federation_browser_smoke.mjs").installDiagnostics>;
  signal: AbortSignal | undefined;
  url: string;
  expectedOrigin: string;
  catalogPath: string;
  applicationKey: ApplicationKey;
  surfaceId: string;
  expectedScope: string;
  readyExpression: string;
  queryPath: string;
  queryId: string;
  queryVersion: number;
  expectedReleaseId?: string | undefined;
  readPublishedHostBody?: boolean;
  navigateSurface?: boolean;
  existingGeneration?: GenerationSelection;
}
export type RepresentativeOptions = Omit<SurfaceOptions, "url" | "queryVersion"> & {
  args: string[];
  argName: string;
  expectedPath: string;
};
export type RepresentativeConfig = Omit<
  RepresentativeOptions,
  "client" | "diagnostics" | "signal" | "args" | "expectedOrigin"
>;
