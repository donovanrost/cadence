export * as decoders from "./decode.ts";
export { DecodeError, decode, type Decoded, type Reader } from "./decode.ts";
export {
  API_BASE,
  describeApiError,
  outcomeUnknown,
  request,
  requestPage,
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
/** U86: lists read item by item; an unreadable item is left out and described. */
export {
  oneItem,
  perItem,
  unshownLine,
  type PerItem,
  type PerItemOptions,
  type Unshown,
} from "./perItem.ts";
/** Schema-driven JSON documents: guards and path helpers instead of `as` (typing §12 A1). */
export {
  childRecord,
  isKeyOf,
  isRecord,
  jsonObject,
  pathGet,
  pathSet,
  recordOf,
  type JsonObject,
} from "./json.ts";
/** Shared entity decoders: one reader per server entity (typing §12 A5). */
export {
  actor,
  actorKinds,
  actorKindWord,
  actorName,
  invitationCore,
  invitationState,
  invitationStates,
  invitedBy,
  orNull,
  role,
  roleText,
  roleWords,
  roles,
  spacecraftRef,
  stationRef,
  type Actor,
  type ActorKind,
  type InvitationState,
  type Role,
  type SpacecraftRef,
  type StationRef,
} from "./entities.ts";
/** Branded resource ids (typing §12C): minted only by these decoders and param readers. */
export {
  missionId,
  scid,
  scidParam,
  scidText,
  spacecraftId,
  spacecraftIdParam,
  stationId,
  stationIdParam,
  type MissionId,
  type Scid,
  type SpacecraftId,
  type StationId,
} from "./ids.ts";
/** Typed server error codes (typing §12 A2): isError, codeOf, detailsOf, fieldErrors. */
export {
  codeOf,
  detailsOf,
  errorCodes,
  fieldErrors,
  hasErrorCode,
  isError,
  knownErrorCode,
  type ErrorCode,
} from "./errors.ts";
