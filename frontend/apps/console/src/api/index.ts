export * as decoders from "./decode.ts";
export { DecodeError, decode, type Decoded, type Reader } from "./decode.ts";
export {
  API_BASE,
  describeApiError,
  outcomeUnknown,
  request,
  setCsrfToken,
  type ApiError,
  type ApiResult,
  type RequestOptions,
} from "./http.ts";
export type { Session, SessionMission, SessionOrganization } from "./session.ts";
export { type RemoteState } from "./remote-state.ts";
export { useRemoteQuery } from "./use-remote-query.ts";
/** Closed vocabularies that keep the raw server word (typing plan §12 A0). */
export { isKnown, knownText, vocabularyText, type Unrecognized } from "./decode.ts";
/** Schema-driven JSON documents: guards and path helpers instead of `as` (typing §12 A1). */
export {
  childRecord,
  isRecord,
  jsonObject,
  pathGet,
  pathSet,
  recordOf,
  type JsonObject,
} from "./json.ts";
