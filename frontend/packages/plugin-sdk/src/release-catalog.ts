import { APPLICATION_HOST_CONTRACT } from "./manifest";

export const SIGNED_FRONTEND_DOCUMENT_SCHEMA = "cadence.signed-frontend-document.v1" as const;
export const FIRST_PARTY_FRONTEND_RELEASE_SCHEMA =
  "cadence.first-party-frontend-release.v1" as const;
export const FIRST_PARTY_FRONTEND_RELEASE_CATALOG_SCHEMA =
  "cadence.first-party-frontend-release-catalog.v1" as const;
export const FRONTEND_RELEASE_ALGORITHM = "ed25519" as const;
export const FRONTEND_RELEASE_PAYLOAD_ENCODING = "base64url-json" as const;
export const SUPPORTED_FRONTEND_VUE_RANGE = "^3.5.40" as const;

const MAX_DOCUMENT_BYTES = 1_000_000;
const MAX_PAYLOAD_BYTES = 750_000;
const MAX_ENCODED_PAYLOAD_BYTES = 1_000_004;
const MAX_KEY_RECORDS = 64;
const MAX_STRING_BYTES = 512;
const MAX_MEDIA_TYPE_BYTES = 128;
const MAX_IDENTIFIER_BYTES = 128;
const MAX_ARTIFACT_PATH_BYTES = 256;
const MAX_ARTIFACTS = 2_048;
const MAX_CATALOG_ENTRIES = 512;
const MAX_ARTIFACT_SIZE = 100_000_000;
const MAX_VERSION = 1_000;
const MAX_SEQUENCE = 1_000_000_000;
const MAX_DEPTH = 16;
const MAX_OBJECT_MEMBERS = 64;
const MAX_ARRAY_ITEMS = 4_096;
const MAX_CATALOG_LIFETIME_MS = 31 * 24 * 60 * 60 * 1_000;

export type SigningRole = "release" | "promotion";

export interface SignedFrontendDocument {
  schema: typeof SIGNED_FRONTEND_DOCUMENT_SCHEMA;
  keyId: string;
  algorithm: typeof FRONTEND_RELEASE_ALGORITHM;
  signingRole: SigningRole;
  payloadEncoding: typeof FRONTEND_RELEASE_PAYLOAD_ENCODING;
  payload: string;
  signature: string;
}

export interface FrontendReleasePublicKey {
  keyId: string;
  algorithm: typeof FRONTEND_RELEASE_ALGORITHM;
  publicKey: string;
  allowedRoles: readonly SigningRole[];
  validFrom: string;
  validUntil: string;
  revokedAt: string | null;
}

type NormalizedFrontendReleasePublicKey = FrontendReleasePublicKey & {
  publicKeyBytes: Uint8Array;
  validFromMs: number;
  validUntilMs: number;
  revokedAtMs: number | null;
};

export type FrontendReleaseKeyRecords =
  | readonly FrontendReleasePublicKey[]
  | Readonly<Record<string, FrontendReleasePublicKey>>;

export interface ReleaseIdentityVersion {
  id: string;
  version: number;
}

export interface ArtifactInventoryEntry {
  path: string;
  sha256: string;
  size: number;
  mediaType: string;
}

export interface HostCompatibility {
  hostContract: typeof APPLICATION_HOST_CONTRACT;
  compatibility: {
    cadenceApplicationContract: 1;
    cadenceSurfaceContract: 1;
    cadenceFederatedRendererContract: 1;
    cadenceThemeContract: 1;
  };
  vueRange: typeof SUPPORTED_FRONTEND_VUE_RANGE;
}

export interface FirstPartyFrontendRelease {
  schema: typeof FIRST_PARTY_FRONTEND_RELEASE_SCHEMA;
  releaseId: string;
  application: ReleaseIdentityVersion;
  package: ReleaseIdentityVersion;
  surface: ReleaseIdentityVersion;
  transport: "module_federation";
  remoteName: string;
  exposedModule: string;
  artifactBaseUrl: string;
  manifest: ArtifactInventoryEntry;
  artifacts: readonly ArtifactInventoryEntry[];
  hostCompatibility: HostCompatibility;
  provenance: {
    sourceRepository: string;
    sourceRevision: string;
    buildId: string;
    builder: string;
    workflow: string;
    builtAt: string;
  };
  releasedAt: string;
}

export interface CatalogIdentity {
  application: ReleaseIdentityVersion;
  package: ReleaseIdentityVersion;
  surface: ReleaseIdentityVersion;
}

export interface FrontendReleaseCatalogEntry {
  identity: CatalogIdentity;
  current: SignedFrontendDocument;
  fallback?: SignedFrontendDocument;
}

export interface FirstPartyFrontendReleaseCatalog {
  schema: typeof FIRST_PARTY_FRONTEND_RELEASE_CATALOG_SCHEMA;
  sequence: number;
  publishedAt: string;
  expiresAt: string;
  entries: readonly FrontendReleaseCatalogEntry[];
}

export interface VerifiedSignedFrontendDocument {
  payload: Record<string, unknown>;
  payloadBytes: Uint8Array;
  keyId: string;
  signingRole: SigningRole;
}

export interface VerifiedCatalogEntry {
  identity: CatalogIdentity;
  current: FirstPartyFrontendRelease;
  fallback?: FirstPartyFrontendRelease;
}

export interface AcceptedCatalogState {
  sequence: number;
  publishedAt: string;
  digest: string;
  entries: readonly VerifiedCatalogEntry[];
}

export interface VerifiedFirstPartyFrontendRelease {
  release: FirstPartyFrontendRelease;
  payload: Record<string, unknown>;
  payloadBytes: Uint8Array;
  keyId: string;
  signingRole: "release";
  digest: string;
}

export interface VerifiedFirstPartyFrontendReleaseCatalog {
  catalog: FirstPartyFrontendReleaseCatalog;
  entries: readonly VerifiedCatalogEntry[];
  payloadBytes: Uint8Array;
  keyId: string;
  signingRole: "promotion";
  digest: string;
  acceptance: "new" | "identical";
  acceptedState: AcceptedCatalogState;
}

export type VerificationErrorCode =
  | "invalid_document"
  | "invalid_type"
  | "unknown_fields"
  | "incomplete_required_fields"
  | "unbounded_value"
  | "invalid_utf8"
  | "invalid_json"
  | "noncanonical_json"
  | "duplicate_json_key"
  | "invalid_scalar"
  | "invalid_base64"
  | "unknown_schema"
  | "schema_role_mismatch"
  | "invalid_algorithm"
  | "invalid_role"
  | "invalid_encoding"
  | "unknown_key"
  | "invalid_key_record"
  | "duplicate_key"
  | "role_not_allowed"
  | "not_yet_valid_key"
  | "expired_key"
  | "revoked_key"
  | "invalid_signature"
  | "crypto_error"
  | "invalid_value"
  | "invalid_timestamp"
  | "invalid_sequence"
  | "invalid_sha256"
  | "release_id_mismatch"
  | "duplicate_identity"
  | "identity_mismatch"
  | "duplicate_release_id"
  | "duplicate_remote_or_exposed_module"
  | "duplicate_artifact_path"
  | "unsorted_artifacts"
  | "unsorted_entries"
  | "unsorted_array"
  | "duplicate_role"
  | "path_traversal"
  | "absolute_path"
  | "backslash_path"
  | "invalid_base_url"
  | "invalid_fallback"
  | "not_yet_published"
  | "expired_catalog"
  | "lower_sequence"
  | "same_sequence_fork"
  | "non_monotonic_publication"
  | "invalid_state"
  | "invalid_state_transition"
  | "fallback_required";

export interface VerificationError {
  code: VerificationErrorCode;
  path: string;
}

export type VerificationResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: VerificationError };

export interface VerifyOptions {
  now?: string | Date;
  allowedOrigins?: readonly string[];
  acceptedState?: AcceptedCatalogState;
}

export async function verifySignedFrontendDocument(
  document: unknown,
  keyRecords: FrontendReleaseKeyRecords,
  options: VerifyOptions = {},
): Promise<VerificationResult<VerifiedSignedFrontendDocument>> {
  try {
    return await verifyEnvelope(document, keyRecords, options);
  } catch {
    return fail("invalid_document", "$");
  }
}

export async function verifyFirstPartyFrontendRelease(
  document: unknown,
  keyRecords: FrontendReleaseKeyRecords,
  options: VerifyOptions = {},
): Promise<VerificationResult<VerifiedFirstPartyFrontendRelease>> {
  try {
    const origins = allowedOrigins(options.allowedOrigins);
    if (!origins.ok) return origins;
    const envelope = await verifyEnvelope(document, keyRecords, options, "release");
    if (!envelope.ok) return envelope;
    const release = await validateRelease(envelope.value.payload, "$.payload", origins.value);
    if (!release.ok) return release;
    return {
      ok: true,
      value: {
        release: release.value,
        payload: envelope.value.payload,
        payloadBytes: envelope.value.payloadBytes,
        keyId: envelope.value.keyId,
        signingRole: "release",
        digest: await digest(envelope.value.payloadBytes),
      },
    };
  } catch {
    return fail("invalid_document", "$");
  }
}

export async function verifyFirstPartyFrontendReleaseCatalog(
  document: unknown,
  keyRecords: FrontendReleaseKeyRecords,
  options: VerifyOptions = {},
): Promise<VerificationResult<VerifiedFirstPartyFrontendReleaseCatalog>> {
  try {
    const origins = allowedOrigins(options.allowedOrigins);
    if (!origins.ok) return origins;
    const envelope = await verifyEnvelope(document, keyRecords, options, "promotion");
    if (!envelope.ok) return envelope;
    const catalog = await validateCatalog(
      envelope.value.payload,
      keyRecords,
      options,
      origins.value,
    );
    if (!catalog.ok) return catalog;
    const now = parseNow(options.now);
    if (!now.ok) return now;
    const current = catalogCurrent(catalog.value, now.value);
    if (!current.ok) return current;
    const catalogDigest = await digest(envelope.value.payloadBytes);
    const admission = await admitCatalog(
      catalog.value,
      catalogDigest,
      options.acceptedState,
      origins.value,
    );
    if (!admission.ok) return admission;
    const acceptedState: AcceptedCatalogState = {
      sequence: catalog.value.sequence,
      publishedAt: catalog.value.publishedAt,
      digest: catalogDigest,
      entries: catalog.value.entries,
    };
    return {
      ok: true,
      value: {
        catalog: envelope.value.payload as unknown as FirstPartyFrontendReleaseCatalog,
        entries: catalog.value.entries,
        payloadBytes: envelope.value.payloadBytes,
        keyId: envelope.value.keyId,
        signingRole: "promotion",
        digest: catalogDigest,
        acceptance: admission.value,
        acceptedState,
      },
    };
  } catch {
    return fail("invalid_document", "$");
  }
}

export const verifyFrontendRelease = verifyFirstPartyFrontendRelease;
export const verifyFrontendReleaseCatalog = verifyFirstPartyFrontendReleaseCatalog;

async function verifyEnvelope(
  document: unknown,
  keyRecords: FrontendReleaseKeyRecords,
  options: VerifyOptions,
  expectedRole?: SigningRole,
): Promise<VerificationResult<VerifiedSignedFrontendDocument>> {
  const decoded = decodeDocument(document);
  if (!decoded.ok) return decoded;
  const envelope = decoded.value;
  const fields = exactFields(
    envelope,
    ["schema", "keyId", "algorithm", "signingRole", "payloadEncoding", "payload", "signature"],
    "$" as const,
  );
  if (!fields.ok) return fields;
  const schema = exactConstant(
    envelope,
    "schema",
    SIGNED_FRONTEND_DOCUMENT_SCHEMA,
    "unknown_schema",
    "$.schema",
  );
  if (!schema.ok) return schema;
  const algorithm = exactConstant(
    envelope,
    "algorithm",
    FRONTEND_RELEASE_ALGORITHM,
    "invalid_algorithm",
    "$.algorithm",
  );
  if (!algorithm.ok) return algorithm;
  if (!isSigningRole(envelope.signingRole)) return fail("invalid_role", "$.signingRole");
  if (expectedRole !== undefined && envelope.signingRole !== expectedRole)
    return fail("schema_role_mismatch", "$.signingRole");
  const encoding = exactConstant(
    envelope,
    "payloadEncoding",
    FRONTEND_RELEASE_PAYLOAD_ENCODING,
    "invalid_encoding",
    "$.payloadEncoding",
  );
  if (!encoding.ok) return encoding;
  const keyIdType = boundedString(envelope.keyId, "$.keyId");
  if (!keyIdType.ok) return keyIdType;
  const keyIdError = safeIdentifier(envelope.keyId, "$.keyId");
  if (keyIdError) return fail(keyIdError.code, keyIdError.path);

  const payloadEncoded = decodeBase64Url(envelope.payload, "$.payload", MAX_ENCODED_PAYLOAD_BYTES);
  if (!payloadEncoded.ok) return payloadEncoded;
  if (payloadEncoded.value.byteLength > MAX_PAYLOAD_BYTES)
    return fail("unbounded_value", "$.payload");
  const signature = decodeBase64Url(envelope.signature, "$.signature", 256);
  if (!signature.ok) return signature;
  if (signature.value.byteLength !== 64) return fail("invalid_value", "$.signature");
  const payloadText = decodeUtf8(payloadEncoded.value, "$.payload");
  if (!payloadText.ok) return payloadText;
  const payload = decodePayload(payloadText.value, "$.payload");
  if (!payload.ok) return payload;
  const schemaRole = payloadSchemaForRole(payload.value, envelope.signingRole);
  if (!schemaRole.ok) return schemaRole;
  const keys = normalizeKeyRecords(keyRecords);
  if (!keys.ok) return keys;
  const now = parseNow(options.now);
  if (!now.ok) return now;
  const key = keys.value.find((candidate) => candidate.keyId === envelope.keyId);
  if (!key) return fail("unknown_key", "$.keyId");
  if (!key.allowedRoles.includes(envelope.signingRole))
    return fail("role_not_allowed", "$.signingRole");
  if (key.revokedAtMs !== null && now.value >= key.revokedAtMs)
    return fail("revoked_key", "$.keyId");
  if (now.value < key.validFromMs) return fail("not_yet_valid_key", "$.keyId");
  if (now.value >= key.validUntilMs) return fail("expired_key", "$.keyId");
  try {
    const imported = await globalThis.crypto.subtle.importKey(
      "raw",
      arrayBuffer(key.publicKeyBytes),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    const valid = await globalThis.crypto.subtle.verify(
      "Ed25519",
      imported,
      arrayBuffer(signature.value),
      arrayBuffer(payloadEncoded.value),
    );
    if (!valid) return fail("invalid_signature", "$.signature");
  } catch {
    return fail("crypto_error", "$.signature");
  }
  return {
    ok: true,
    value: {
      payload: payload.value,
      payloadBytes: payloadEncoded.value,
      keyId: envelope.keyId as string,
      signingRole: envelope.signingRole as SigningRole,
    },
  };
}

function decodeDocument(document: unknown): VerificationResult<Record<string, unknown>> {
  if (typeof document === "string") {
    const bytes = new TextEncoder().encode(document);
    if (bytes.byteLength > MAX_DOCUMENT_BYTES) return fail("unbounded_value", "$");
    const parsed = decodePayload(document, "$");
    if (!parsed.ok) return parsed;
    if (!isRecord(parsed.value)) return fail("invalid_type", "$");
    return { ok: true, value: parsed.value };
  }
  if (!isRecord(document)) return fail("invalid_type", "$");
  const tree = validateJsonTree(document, "$");
  if (!tree.ok) return tree;
  return { ok: true, value: document };
}

function decodePayload(text: string, path: string): VerificationResult<Record<string, unknown>> {
  const preflight = preflightJson(text, path);
  if (!preflight.ok) return preflight;
  let value: unknown;
  try {
    value = JSON.parse(text) as unknown;
  } catch {
    return fail("invalid_json", path);
  }
  if (canonicalJson(value) !== text) return fail("noncanonical_json", path);
  const tree = validateJsonTree(value, path);
  if (!tree.ok) return tree;
  if (!isRecord(value)) return fail("invalid_type", path);
  return { ok: true, value };
}

function payloadSchemaForRole(
  payload: Record<string, unknown>,
  role: SigningRole,
): VerificationResult<null> {
  const expected =
    role === "release"
      ? FIRST_PARTY_FRONTEND_RELEASE_SCHEMA
      : FIRST_PARTY_FRONTEND_RELEASE_CATALOG_SCHEMA;
  if (!("schema" in payload)) return fail("incomplete_required_fields", "$.payload.schema");
  if (payload.schema !== expected) return fail("schema_role_mismatch", "$.payload.schema");
  return { ok: true, value: null };
}

async function validateRelease(
  value: Record<string, unknown>,
  path: string,
  origins: readonly string[],
): Promise<VerificationResult<FirstPartyFrontendRelease>> {
  const fields = exactFields(
    value,
    [
      "schema",
      "releaseId",
      "application",
      "package",
      "surface",
      "transport",
      "remoteName",
      "exposedModule",
      "artifactBaseUrl",
      "manifest",
      "artifacts",
      "hostCompatibility",
      "provenance",
      "releasedAt",
    ],
    path,
  );
  if (!fields.ok) return fields;
  const schema = exactConstant(
    value,
    "schema",
    FIRST_PARTY_FRONTEND_RELEASE_SCHEMA,
    "unknown_schema",
    `${path}.schema`,
  );
  if (!schema.ok) return schema;
  for (const key of ["application", "package", "surface"] as const) {
    const identity = identityVersion(value[key], `${path}.${key}`);
    if (!identity.ok) return identity;
  }
  const releaseId = await releaseIdValue(value.releaseId, `${path}.releaseId`, value);
  if (!releaseId.ok) return releaseId;
  const transport = exactConstant(
    value,
    "transport",
    "module_federation",
    "invalid_value",
    `${path}.transport`,
  );
  if (!transport.ok) return transport;
  const remote = safeIdentifier(value.remoteName, `${path}.remoteName`);
  if (remote) return fail(remote.code, remote.path);
  if (typeof value.exposedModule !== "string")
    return fail("invalid_value", `${path}.exposedModule`);
  const exposed = boundedString(value.exposedModule, `${path}.exposedModule`);
  if (!exposed.ok) return exposed;
  if (!/^\.[/][A-Za-z][A-Za-z0-9._-]{0,127}$/.test(value.exposedModule as string))
    return fail("invalid_value", `${path}.exposedModule`);
  const artifacts = validateArtifacts(value.manifest, value.artifacts, path);
  if (!artifacts.ok) return artifacts;
  const host = validateHostCompatibility(value.hostCompatibility, `${path}.hostCompatibility`);
  if (!host.ok) return host;
  const provenance = validateProvenance(value.provenance, `${path}.provenance`);
  if (!provenance.ok) return provenance;
  const releasedAt = parseTimestamp(value.releasedAt, `${path}.releasedAt`);
  if (!releasedAt.ok) return releasedAt;
  const base = validateArtifactBaseUrl(
    value.artifactBaseUrl,
    value,
    origins,
    `${path}.artifactBaseUrl`,
  );
  if (!base.ok) return base;
  return { ok: true, value: value as unknown as FirstPartyFrontendRelease };
}

async function releaseIdValue(
  value: unknown,
  path: string,
  release: Record<string, unknown>,
): Promise<VerificationResult<null>> {
  if (typeof value !== "string") return fail("invalid_sha256", path);
  const bounded = boundedString(value, path);
  if (!bounded.ok) return bounded;
  if (!/^sha256:[0-9a-f]{64}$/.test(value as string)) return fail("invalid_sha256", path);
  const logical = { ...release };
  delete logical.releaseId;
  delete logical.artifactBaseUrl;
  const expected = await digest(new TextEncoder().encode(canonicalJson(logical)));
  if (value !== expected) return fail("release_id_mismatch", path);
  return { ok: true, value: null };
}

function identityVersion(value: unknown, path: string): VerificationResult<ReleaseIdentityVersion> {
  if (!isRecord(value)) return fail("invalid_type", path);
  const fields = exactFields(value, ["id", "version"], path);
  if (!fields.ok) return fields;
  const id = safeIdentifier(value.id, `${path}.id`);
  if (id) return fail(id.code, id.path);
  const version = value.version;
  if (
    typeof version !== "number" ||
    !Number.isSafeInteger(version) ||
    version < 1 ||
    version > MAX_VERSION
  )
    return fail("invalid_value", `${path}.version`);
  return { ok: true, value: value as unknown as ReleaseIdentityVersion };
}

function validateArtifacts(
  manifest: unknown,
  artifacts: unknown,
  path: string,
): VerificationResult<readonly ArtifactInventoryEntry[]> {
  if (!Array.isArray(artifacts)) return fail("invalid_type", `${path}.artifacts`);
  if (artifacts.length === 0) return fail("incomplete_required_fields", `${path}.artifacts`);
  if (artifacts.length > MAX_ARTIFACTS) return fail("unbounded_value", `${path}.artifacts`);
  const manifestResult = validateArtifact(manifest, `${path}.manifest`);
  if (!manifestResult.ok) return manifestResult;
  const entries: ArtifactInventoryEntry[] = [];
  const paths = new Set<string>();
  let previous: string | undefined;
  for (let index = 0; index < artifacts.length; index += 1) {
    const artifact = validateArtifact(artifacts[index], `${path}.artifacts[${index}]`);
    if (!artifact.ok) return artifact;
    if (previous !== undefined && compareUtf8(previous, artifact.value.path) >= 0)
      return fail("unsorted_artifacts", `${path}.artifacts[${index}].path`);
    if (paths.has(artifact.value.path))
      return fail("duplicate_artifact_path", `${path}.artifacts[${index}].path`);
    previous = artifact.value.path;
    paths.add(artifact.value.path);
    entries.push(artifact.value);
  }
  if (!entries.some((entry) => canonicalJson(entry) === canonicalJson(manifestResult.value)))
    return fail("incomplete_required_fields", `${path}.manifest`);
  return { ok: true, value: entries };
}

function validateArtifact(
  value: unknown,
  path: string,
): VerificationResult<ArtifactInventoryEntry> {
  if (!isRecord(value)) return fail("invalid_type", path);
  const fields = exactFields(value, ["path", "sha256", "size", "mediaType"], path);
  if (!fields.ok) return fields;
  if (typeof value.path !== "string") return fail("invalid_value", `${path}.path`);
  const boundedPath = boundedString(value.path, `${path}.path`);
  if (!boundedPath.ok) return boundedPath;
  const artifactPath = boundedPath.value;
  if (new TextEncoder().encode(artifactPath).byteLength > MAX_ARTIFACT_PATH_BYTES)
    return fail("unbounded_value", `${path}.path`);
  if (artifactPath === "" || artifactPath.startsWith("/"))
    return fail(artifactPath.startsWith("/") ? "absolute_path" : "invalid_value", `${path}.path`);
  if (artifactPath.includes("\\")) return fail("backslash_path", `${path}.path`);
  if (artifactPath.split("/").some((part) => part === "" || part === "." || part === ".."))
    return fail("path_traversal", `${path}.path`);
  if (typeof value.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(value.sha256))
    return fail("invalid_sha256", `${path}.sha256`);
  const size = value.size;
  if (
    typeof size !== "number" ||
    !Number.isSafeInteger(size) ||
    size < 0 ||
    size > MAX_ARTIFACT_SIZE
  )
    return fail("invalid_value", `${path}.size`);
  if (typeof value.mediaType !== "string") return fail("invalid_value", `${path}.mediaType`);
  const media = boundedString(value.mediaType, `${path}.mediaType`);
  if (!media.ok) return media;
  if (new TextEncoder().encode(media.value).byteLength > MAX_MEDIA_TYPE_BYTES)
    return fail("unbounded_value", `${path}.mediaType`);
  if (
    !/^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/.test(
      value.mediaType as string,
    )
  )
    return fail("invalid_value", `${path}.mediaType`);
  return { ok: true, value: value as unknown as ArtifactInventoryEntry };
}

function validateHostCompatibility(
  value: unknown,
  path: string,
): VerificationResult<HostCompatibility> {
  if (!isRecord(value)) return fail("invalid_type", path);
  const fields = exactFields(value, ["hostContract", "compatibility", "vueRange"], path);
  if (!fields.ok) return fields;
  const hostContract = exactConstant(
    value,
    "hostContract",
    APPLICATION_HOST_CONTRACT,
    "invalid_value",
    `${path}.hostContract`,
  );
  if (!hostContract.ok) return hostContract;
  if (!isRecord(value.compatibility)) return fail("invalid_type", `${path}.compatibility`);
  const compatibility = exactFields(
    value.compatibility,
    [
      "cadenceApplicationContract",
      "cadenceSurfaceContract",
      "cadenceFederatedRendererContract",
      "cadenceThemeContract",
    ],
    `${path}.compatibility`,
  );
  if (!compatibility.ok) return compatibility;
  for (const key of [
    "cadenceApplicationContract",
    "cadenceSurfaceContract",
    "cadenceFederatedRendererContract",
    "cadenceThemeContract",
  ] as const) {
    if (value.compatibility[key] !== 1)
      return fail("invalid_value", `${path}.compatibility.${key}`);
  }
  const vueRange = exactConstant(
    value,
    "vueRange",
    SUPPORTED_FRONTEND_VUE_RANGE,
    "invalid_value",
    `${path}.vueRange`,
  );
  if (!vueRange.ok) return vueRange;
  return { ok: true, value: value as unknown as HostCompatibility };
}

function validateProvenance(value: unknown, path: string): VerificationResult<null> {
  if (!isRecord(value)) return fail("invalid_type", path);
  const fields = exactFields(
    value,
    ["sourceRepository", "sourceRevision", "buildId", "builder", "workflow", "builtAt"],
    path,
  );
  if (!fields.ok) return fields;
  const source = strictHttpsUrl(value.sourceRepository, `${path}.sourceRepository`);
  if (!source.ok) return source;
  if (
    typeof value.sourceRevision !== "string" ||
    !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(value.sourceRevision)
  )
    return fail("invalid_value", `${path}.sourceRevision`);
  for (const key of ["buildId", "builder", "workflow"] as const) {
    const bounded = boundedString(value[key], `${path}.${key}`);
    if (!bounded.ok) return bounded;
  }
  const built = parseTimestamp(value.builtAt, `${path}.builtAt`);
  if (!built.ok) return built;
  return { ok: true, value: null };
}

function validateArtifactBaseUrl(
  value: unknown,
  release: Record<string, unknown>,
  origins: readonly string[],
  path: string,
): VerificationResult<null> {
  const parsed = strictHttpsUrl(value, path);
  if (!parsed.ok) return parsed;
  if (!origins.includes(parsed.value.origin)) return fail("invalid_base_url", path);
  const application = release.application;
  if (
    !isRecord(application) ||
    typeof application.id !== "string" ||
    typeof release.releaseId !== "string"
  )
    return fail("invalid_base_url", path);
  const expected = `/releases/${application.id}/${release.releaseId}/artifacts/`;
  if (parsed.value.path !== expected) return fail("invalid_base_url", path);
  return { ok: true, value: null };
}

async function validateCatalog(
  value: Record<string, unknown>,
  keyRecords: FrontendReleaseKeyRecords,
  options: VerifyOptions,
  origins: readonly string[],
): Promise<
  VerificationResult<{
    sequence: number;
    publishedAt: string;
    expiresAt: string;
    entries: readonly VerifiedCatalogEntry[];
  }>
> {
  const path = "$.payload";
  const fields = exactFields(
    value,
    ["schema", "sequence", "publishedAt", "expiresAt", "entries"],
    path,
  );
  if (!fields.ok) return fields;
  const schema = exactConstant(
    value,
    "schema",
    FIRST_PARTY_FRONTEND_RELEASE_CATALOG_SCHEMA,
    "unknown_schema",
    `${path}.schema`,
  );
  if (!schema.ok) return schema;
  const sequence = value.sequence;
  if (
    typeof sequence !== "number" ||
    !Number.isSafeInteger(sequence) ||
    sequence < 1 ||
    sequence > MAX_SEQUENCE
  )
    return fail("invalid_sequence", `${path}.sequence`);
  const published = parseTimestamp(value.publishedAt, `${path}.publishedAt`);
  if (!published.ok) return published;
  const expires = parseTimestamp(value.expiresAt, `${path}.expiresAt`);
  if (!expires.ok) return expires;
  if (expires.value <= published.value) return fail("invalid_timestamp", `${path}.expiresAt`);
  if (expires.value - published.value > MAX_CATALOG_LIFETIME_MS)
    return fail("unbounded_value", path);
  if (!Array.isArray(value.entries)) return fail("invalid_type", `${path}.entries`);
  if (value.entries.length === 0) return fail("incomplete_required_fields", `${path}.entries`);
  if (value.entries.length > MAX_CATALOG_ENTRIES) return fail("unbounded_value", `${path}.entries`);
  const entries: VerifiedCatalogEntry[] = [];
  const identities = new Set<string>();
  const releaseIds = new Set<string>();
  const names = new Map<string, string>();
  let previous: CatalogIdentity | undefined;
  for (let index = 0; index < value.entries.length; index += 1) {
    const itemPath = `${path}.entries[${index}]`;
    const entry = value.entries[index];
    if (!isRecord(entry)) return fail("invalid_type", itemPath);
    const entryFields = exactFields(entry, ["identity", "current"], itemPath, ["fallback"]);
    if (!entryFields.ok) return entryFields;
    const identity = catalogIdentity(entry.identity, `${itemPath}.identity`);
    if (!identity.ok) return identity;
    const current = await verifyNestedRelease(
      entry.current,
      keyRecords,
      options,
      origins,
      `${itemPath}.current`,
    );
    if (!current.ok) return current;
    const fallback =
      entry.fallback === undefined
        ? undefined
        : await verifyNestedRelease(
            entry.fallback,
            keyRecords,
            options,
            origins,
            `${itemPath}.fallback`,
          );
    if (fallback !== undefined && !fallback.ok) return fallback;
    const fallbackValue = fallback?.ok ? fallback.value : undefined;
    if (identityKey(current.value.release) !== identityKey(identity.value))
      return fail("identity_mismatch", `${itemPath}.current`);
    if (
      fallbackValue !== undefined &&
      identityKey(fallbackValue.release) !== identityKey(identity.value)
    )
      return fail("identity_mismatch", `${itemPath}.fallback`);
    const currentReleased = parseTimestamp(
      current.value.release.releasedAt,
      `${itemPath}.current.releasedAt`,
    );
    if (!currentReleased.ok) return currentReleased;
    if (currentReleased.value > published.value)
      return fail("not_yet_published", `${itemPath}.current.releasedAt`);
    if (fallbackValue !== undefined) {
      const fallbackReleased = parseTimestamp(
        fallbackValue.release.releasedAt,
        `${itemPath}.fallback.releasedAt`,
      );
      if (!fallbackReleased.ok) return fallbackReleased;
      if (fallbackReleased.value > published.value)
        return fail("not_yet_published", `${itemPath}.fallback.releasedAt`);
    }
    if (
      fallbackValue !== undefined &&
      current.value.release.releaseId === fallbackValue.release.releaseId
    )
      return fail("invalid_fallback", `${itemPath}.fallback`);
    if (previous !== undefined && compareIdentity(previous, identity.value) >= 0)
      return fail("unsorted_entries", `${itemPath}.identity`);
    previous = identity.value;
    const idKey = identityKey(identity.value);
    if (identities.has(idKey)) return fail("duplicate_identity", `${itemPath}.identity`);
    identities.add(idKey);
    const releaseIdsForEntry = [
      current.value.release,
      ...(fallbackValue === undefined ? [] : [fallbackValue.release]),
    ];
    if (releaseIdsForEntry.some((release) => releaseIds.has(release.releaseId)))
      return fail("duplicate_release_id", itemPath);
    for (const release of releaseIdsForEntry) {
      releaseIds.add(release.releaseId);
    }
    let unique = uniqueName(
      names,
      current.value.release.remoteName,
      idKey,
      `${itemPath}.current.remoteName`,
    );
    if (!unique.ok) return unique;
    unique = uniqueName(
      names,
      fallbackValue?.release.remoteName,
      idKey,
      `${itemPath}.fallback.remoteName`,
    );
    if (!unique.ok) return unique;
    unique = uniqueName(
      names,
      current.value.release.exposedModule,
      idKey,
      `${itemPath}.current.exposedModule`,
    );
    if (!unique.ok) return unique;
    unique = uniqueName(
      names,
      fallbackValue?.release.exposedModule,
      idKey,
      `${itemPath}.fallback.exposedModule`,
    );
    if (!unique.ok) return unique;
    entries.push({
      identity: identity.value,
      current: current.value.release,
      ...(fallbackValue === undefined ? {} : { fallback: fallbackValue.release }),
    });
  }
  return {
    ok: true,
    value: {
      sequence: value.sequence as number,
      publishedAt: value.publishedAt as string,
      expiresAt: value.expiresAt as string,
      entries,
    },
  };
}

function catalogCurrent(
  catalog: { publishedAt: string; expiresAt: string },
  now: number,
): VerificationResult<null> {
  const published = parseTimestamp(catalog.publishedAt, "$.payload.publishedAt");
  if (!published.ok) return published;
  const expires = parseTimestamp(catalog.expiresAt, "$.payload.expiresAt");
  if (!expires.ok) return expires;
  if (now < published.value) return fail("not_yet_published", "$.payload.publishedAt");
  if (now >= expires.value) return fail("expired_catalog", "$.payload.expiresAt");
  return { ok: true, value: null };
}

function catalogIdentity(value: unknown, path: string): VerificationResult<CatalogIdentity> {
  if (!isRecord(value)) return fail("invalid_type", path);
  const fields = exactFields(value, ["application", "package", "surface"], path);
  if (!fields.ok) return fields;
  const application = identityVersion(value.application, `${path}.application`);
  if (!application.ok) return application;
  const pkg = identityVersion(value.package, `${path}.package`);
  if (!pkg.ok) return pkg;
  const surface = identityVersion(value.surface, `${path}.surface`);
  if (!surface.ok) return surface;
  return {
    ok: true,
    value: { application: application.value, package: pkg.value, surface: surface.value },
  };
}

async function verifyNestedRelease(
  document: unknown,
  keys: FrontendReleaseKeyRecords,
  options: VerifyOptions,
  origins: readonly string[],
  path: string,
): Promise<VerificationResult<VerifiedFirstPartyFrontendRelease>> {
  const result = await verifyEnvelope(document, keys, options, "release");
  if (!result.ok) return { ok: false, error: prefixError(result.error, path) };
  const release = await validateRelease(result.value.payload, `${path}.payload`, origins);
  if (!release.ok) return release;
  return {
    ok: true,
    value: {
      release: release.value,
      payload: result.value.payload,
      payloadBytes: result.value.payloadBytes,
      keyId: result.value.keyId,
      signingRole: "release",
      digest: await digest(result.value.payloadBytes),
    },
  };
}

async function admitCatalog(
  catalog: { sequence: number; publishedAt: string; entries: readonly VerifiedCatalogEntry[] },
  digestValue: string,
  state: AcceptedCatalogState | undefined,
  origins: readonly string[],
): Promise<VerificationResult<"new" | "identical">> {
  if (state === undefined) return { ok: true, value: "new" };
  const validState = await validateState(state, origins);
  if (!validState.ok) return validState;
  const catalogPublished = parseTimestamp(catalog.publishedAt, "$.payload.publishedAt");
  if (!catalogPublished.ok) return catalogPublished;
  const statePublished = parseTimestamp(state.publishedAt, "$.acceptedState.publishedAt");
  if (!statePublished.ok) return fail("invalid_state", statePublished.error.path);
  const currentIds = new Set(catalog.entries.map((entry) => identityKey(entry.identity)));
  const previousIds = new Set(state.entries.map((entry) => identityKey(entry.identity)));
  if (currentIds.size !== previousIds.size || [...currentIds].some((id) => !previousIds.has(id)))
    return fail("invalid_state_transition", "$.payload.entries");
  if (catalog.sequence < state.sequence) return fail("lower_sequence", "$.payload.sequence");
  if (catalog.sequence === state.sequence && digestValue === state.digest)
    return catalogPublished.value === statePublished.value
      ? { ok: true, value: "identical" }
      : fail("same_sequence_fork", "$.payload.sequence");
  if (catalog.sequence === state.sequence) return fail("same_sequence_fork", "$.payload.sequence");
  if (catalogPublished.value <= statePublished.value)
    return fail("non_monotonic_publication", "$.payload.publishedAt");
  const prior = new Map(state.entries.map((entry) => [identityKey(entry.identity), entry]));
  for (const entry of catalog.entries) {
    const previous = prior.get(identityKey(entry.identity));
    if (!previous) return fail("invalid_state_transition", "$.payload.entries");
    if (entry.current.releaseId === previous.current.releaseId)
      return fail("invalid_state_transition", "$.payload.entries");
    if (entry.fallback === undefined) return fail("fallback_required", "$.payload.entries");
    if (
      previous.fallback !== undefined &&
      entry.current.releaseId === previous.fallback.releaseId &&
      entry.fallback.releaseId === previous.current.releaseId
    )
      continue;
    if (entry.fallback.releaseId !== previous.current.releaseId)
      return fail("invalid_state_transition", "$.payload.entries");
  }
  return { ok: true, value: "new" };
}

async function validateState(
  state: AcceptedCatalogState,
  origins: readonly string[],
): Promise<VerificationResult<null>> {
  if (!isRecord(state) || !exactKeys(state, ["sequence", "publishedAt", "digest", "entries"]))
    return fail("invalid_state", "$.acceptedState");
  if (!Number.isInteger(state.sequence) || state.sequence < 1 || state.sequence > MAX_SEQUENCE)
    return fail("invalid_state", "$.acceptedState");
  const statePublished = parseTimestamp(state.publishedAt, "$.acceptedState.publishedAt");
  if (!statePublished.ok) return fail("invalid_state", "$.acceptedState.publishedAt");
  if (!/^sha256:[0-9a-f]{64}$/.test(state.digest))
    return fail("invalid_state", "$.acceptedState.digest");
  if (!Array.isArray(state.entries) || state.entries.length === 0)
    return fail("invalid_state", "$.acceptedState.entries");
  if (state.entries.length > MAX_CATALOG_ENTRIES)
    return fail("invalid_state", "$.acceptedState.entries");
  const identities = new Set<string>();
  const releaseIds = new Set<string>();
  const names = new Map<string, string>();
  let previousIdentity: CatalogIdentity | undefined;
  for (let index = 0; index < state.entries.length; index += 1) {
    const entry = state.entries[index];
    if (
      !isRecord(entry) ||
      !exactKeys(entry, [
        "identity",
        "current",
        ...((entry.fallback === undefined ? [] : ["fallback"]) as string[]),
      ])
    )
      return fail("invalid_state", `$.acceptedState.entries[${index}]`);
    const identity = catalogIdentity(entry.identity, `$.acceptedState.entries[${index}].identity`);
    if (!identity.ok) return fail("invalid_state", `$.acceptedState.entries[${index}].identity`);
    if (!isRecord(entry.current))
      return fail("invalid_state", `$.acceptedState.entries[${index}].current`);
    const current = await validateRelease(
      entry.current,
      `$.acceptedState.entries[${index}].current`,
      origins,
    );
    if (!current.ok) return fail("invalid_state", current.error.path);
    if (previousIdentity !== undefined && compareIdentity(previousIdentity, identity.value) >= 0)
      return fail("invalid_state", `$.acceptedState.entries[${index}].identity`);
    previousIdentity = identity.value;
    const identityValue = identityKey(identity.value);
    if (identityKey(current.value) !== identityValue)
      return fail("invalid_state", `$.acceptedState.entries[${index}].current`);
    const currentReleased = parseTimestamp(
      current.value.releasedAt,
      `$.acceptedState.entries[${index}].current.releasedAt`,
    );
    if (!currentReleased.ok) return fail("invalid_state", currentReleased.error.path);
    if (currentReleased.value > statePublished.value)
      return fail("invalid_state", `$.acceptedState.entries[${index}].current.releasedAt`);
    let fallbackValue: FirstPartyFrontendRelease | undefined;
    const releases = [current.value];
    if (entry.fallback !== undefined) {
      if (!isRecord(entry.fallback))
        return fail("invalid_state", `$.acceptedState.entries[${index}].fallback`);
      const fallback = await validateRelease(
        entry.fallback,
        `$.acceptedState.entries[${index}].fallback`,
        origins,
      );
      if (!fallback.ok) return fail("invalid_state", fallback.error.path);
      if (identityKey(fallback.value) !== identityValue)
        return fail("invalid_state", `$.acceptedState.entries[${index}].fallback`);
      const fallbackReleased = parseTimestamp(
        fallback.value.releasedAt,
        `$.acceptedState.entries[${index}].fallback.releasedAt`,
      );
      if (!fallbackReleased.ok) return fail("invalid_state", fallbackReleased.error.path);
      if (fallbackReleased.value > statePublished.value)
        return fail("invalid_state", `$.acceptedState.entries[${index}].fallback.releasedAt`);
      if (fallback.value.releaseId === current.value.releaseId)
        return fail("invalid_state", `$.acceptedState.entries[${index}].fallback`);
      fallbackValue = fallback.value;
      releases.push(fallback.value);
    }
    if (identities.has(identityValue))
      return fail("invalid_state", `$.acceptedState.entries[${index}].identity`);
    identities.add(identityValue);
    if (releases.some((release) => releaseIds.has(release.releaseId)))
      return fail("invalid_state", `$.acceptedState.entries[${index}]`);
    for (const release of releases) {
      releaseIds.add(release.releaseId);
    }
    let unique = uniqueName(
      names,
      current.value.remoteName,
      identityValue,
      `$.acceptedState.entries[${index}].current.remoteName`,
    );
    if (!unique.ok)
      return fail("invalid_state", `$.acceptedState.entries[${index}].current.remoteName`);
    unique = uniqueName(
      names,
      fallbackValue?.remoteName,
      identityValue,
      `$.acceptedState.entries[${index}].fallback.remoteName`,
    );
    if (!unique.ok)
      return fail("invalid_state", `$.acceptedState.entries[${index}].fallback.remoteName`);
    unique = uniqueName(
      names,
      current.value.exposedModule,
      identityValue,
      `$.acceptedState.entries[${index}].current.exposedModule`,
    );
    if (!unique.ok)
      return fail("invalid_state", `$.acceptedState.entries[${index}].current.exposedModule`);
    unique = uniqueName(
      names,
      fallbackValue?.exposedModule,
      identityValue,
      `$.acceptedState.entries[${index}].fallback.exposedModule`,
    );
    if (!unique.ok)
      return fail("invalid_state", `$.acceptedState.entries[${index}].fallback.exposedModule`);
  }
  return { ok: true, value: null };
}

function normalizeKeyRecords(
  records: FrontendReleaseKeyRecords,
): VerificationResult<NormalizedFrontendReleasePublicKey[]> {
  const values: Array<{ trustKey?: string; value: unknown }> = [];
  if (Array.isArray(records)) {
    if (records.length > MAX_KEY_RECORDS) return fail("unbounded_value", "$.keys");
    values.push(...records.map((value) => ({ value })));
  } else if (isRecord(records)) {
    if ("keyId" in records) values.push({ value: records });
    else {
      const entries = Object.entries(records).sort(([left], [right]) => compareUtf8(left, right));
      if (entries.length > MAX_KEY_RECORDS) return fail("unbounded_value", "$.keys");
      values.push(...entries.map(([trustKey, value]) => ({ trustKey, value })));
    }
  } else return fail("invalid_key_record", "$.keys");
  const normalized: NormalizedFrontendReleasePublicKey[] = [];
  const ids = new Set<string>();
  for (let index = 0; index < values.length; index += 1) {
    const result = normalizeKeyRecord(values[index]!.value, `$.keys[${index}]`);
    if (!result.ok) return result;
    if (values[index]!.trustKey !== undefined) {
      const trustKey = boundedString(values[index]!.trustKey, `$.keys[${index}]`);
      if (!trustKey.ok || trustKey.value !== result.value.keyId)
        return fail("invalid_key_record", `$.keys[${index}]`);
    }
    if (ids.has(result.value.keyId)) return fail("duplicate_key", `$.keys[${index}].keyId`);
    ids.add(result.value.keyId);
    normalized.push(result.value);
  }
  return { ok: true, value: normalized };
}

function normalizeKeyRecord(
  value: unknown,
  path: string,
): VerificationResult<NormalizedFrontendReleasePublicKey> {
  if (!isRecord(value)) return fail("invalid_key_record", path);
  const fields = exactFields(
    value,
    ["keyId", "algorithm", "publicKey", "allowedRoles", "validFrom", "validUntil", "revokedAt"],
    path,
  );
  if (!fields.ok) return fail("invalid_key_record", fields.error.path);
  const id = safeIdentifier(value.keyId, `${path}.keyId`);
  if (id) return fail("invalid_key_record", `${path}.keyId`);
  if (value.algorithm !== FRONTEND_RELEASE_ALGORITHM)
    return fail("invalid_key_record", `${path}.algorithm`);
  const publicKey = decodeBase64Url(value.publicKey, `${path}.publicKey`, 128);
  if (!publicKey.ok || publicKey.value.byteLength !== 32)
    return fail("invalid_key_record", `${path}.publicKey`);
  if (
    !Array.isArray(value.allowedRoles) ||
    value.allowedRoles.length === 0 ||
    value.allowedRoles.length > 2
  )
    return fail("invalid_key_record", `${path}.allowedRoles`);
  if (
    !value.allowedRoles.every(isSigningRole) ||
    new Set(value.allowedRoles).size !== value.allowedRoles.length
  )
    return fail("invalid_key_record", `${path}.allowedRoles`);
  if ([...value.allowedRoles].sort().join(",") !== [...value.allowedRoles].join(","))
    return fail("invalid_key_record", `${path}.allowedRoles`);
  const from = parseTimestamp(value.validFrom, `${path}.validFrom`);
  if (!from.ok) return fail("invalid_key_record", from.error.path);
  const until = parseTimestamp(value.validUntil, `${path}.validUntil`);
  if (!until.ok) return fail("invalid_key_record", until.error.path);
  if (until.value <= from.value) return fail("invalid_key_record", `${path}.validUntil`);
  let revokedAtMs: number | null = null;
  if (value.revokedAt !== null) {
    const revoked = parseTimestamp(value.revokedAt, `${path}.revokedAt`);
    if (!revoked.ok) return fail("invalid_key_record", revoked.error.path);
    if (revoked.value < from.value) return fail("invalid_key_record", `${path}.revokedAt`);
    revokedAtMs = revoked.value;
  }
  return {
    ok: true,
    value: {
      ...(value as unknown as FrontendReleasePublicKey),
      publicKeyBytes: publicKey.value,
      validFromMs: from.value,
      validUntilMs: until.value,
      revokedAtMs,
    },
  };
}

function allowedOrigins(
  value: readonly string[] | undefined,
): VerificationResult<readonly string[]> {
  if (!Array.isArray(value) || value.length === 0)
    return fail("invalid_base_url", "$.allowedOrigins");
  if (value.length > MAX_KEY_RECORDS) return fail("unbounded_value", "$.allowedOrigins");
  const seen = new Set<string>();
  for (let index = 0; index < value.length; index += 1) {
    const parsed = strictHttpsUrl(value[index], `$.allowedOrigins[${index}]`);
    if (!parsed.ok) return parsed;
    if (parsed.value.path !== "" || value[index] !== parsed.value.origin)
      return fail("invalid_base_url", `$.allowedOrigins[${index}]`);
    if (seen.has(parsed.value.origin))
      return fail("invalid_base_url", `$.allowedOrigins[${index}]`);
    seen.add(parsed.value.origin);
  }
  return { ok: true, value: [...seen] };
}

type StrictHttpsUrl = { origin: string; path: string };

function strictHttpsUrl(value: unknown, path: string): VerificationResult<StrictHttpsUrl> {
  if (typeof value !== "string") return fail("invalid_base_url", path);
  const bounded = boundedString(value, path);
  if (!bounded.ok) return bounded;
  if (
    bounded.value
      .split("")
      .some((character) => character.charCodeAt(0) <= 0x20 || "\\%?#".includes(character)) ||
    !bounded.value.startsWith("https://")
  )
    return fail("invalid_base_url", path);
  const rest = bounded.value.slice("https://".length);
  const slash = rest.indexOf("/");
  const authority = slash === -1 ? rest : rest.slice(0, slash);
  const rawPath = slash === -1 ? "" : rest.slice(slash);
  const authorityMatch = authority.match(
    /^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)(?::([1-9][0-9]{0,4}))?$/,
  );
  if (!authorityMatch) return fail("invalid_base_url", path);
  const port = authorityMatch[2];
  if (port !== undefined && (Number(port) > 65_535 || Number(port) === 443))
    return fail("invalid_base_url", path);
  return { ok: true, value: { origin: `https://${authority}`, path: rawPath } };
}

function parseNow(value: string | Date | undefined): VerificationResult<number> {
  if (value === undefined) return fail("invalid_timestamp", "$.now");
  if (value instanceof Date) {
    const milliseconds = value.getTime();
    return Number.isFinite(milliseconds) && milliseconds >= 0
      ? { ok: true, value: milliseconds }
      : fail("invalid_timestamp", "$.now");
  }
  return parseTimestamp(value, "$.now");
}

function parseTimestamp(value: unknown, path: string): VerificationResult<number> {
  const bounded = boundedString(value, path);
  if (!bounded.ok || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(bounded.value))
    return fail("invalid_timestamp", path);
  const match = bounded.value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{3}))?Z$/,
  );
  if (!match) return fail("invalid_timestamp", path);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const millisecond = Number(match[7] ?? "0");
  if (
    year < 1970 ||
    year > 9999 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    hour > 23 ||
    minute > 59 ||
    second > 59
  )
    return fail("invalid_timestamp", path);
  const milliseconds = Date.UTC(year, month - 1, day, hour, minute, second, millisecond);
  const date = new Date(milliseconds);
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day ||
    date.getUTCHours() !== hour ||
    date.getUTCMinutes() !== minute ||
    date.getUTCSeconds() !== second ||
    date.getUTCMilliseconds() !== millisecond
  )
    return fail("invalid_timestamp", path);
  return { ok: true, value: milliseconds };
}

function exactFields(
  value: Record<string, unknown>,
  required: readonly string[],
  path: string,
  optional: readonly string[] = [],
): VerificationResult<null> {
  const keys = Object.keys(value);
  if (keys.some((key) => !required.includes(key) && !optional.includes(key)))
    return fail("unknown_fields", path);
  if (required.some((key) => !(key in value))) return fail("incomplete_required_fields", path);
  return { ok: true, value: null };
}

function exactConstant<T extends string>(
  value: Record<string, unknown>,
  key: string,
  expected: T,
  code: VerificationErrorCode,
  path: string,
): VerificationResult<T> {
  if (!(key in value)) return fail("incomplete_required_fields", path);
  if (value[key] === expected) return { ok: true, value: expected };
  if (typeof value[key] === "string") return fail(code, path);
  return fail("invalid_type", path);
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  return Object.keys(value).length === expected.length && expected.every((key) => key in value);
}

function boundedString(value: unknown, path: string): VerificationResult<string> {
  if (typeof value !== "string") return fail("invalid_type", path);
  if (new TextEncoder().encode(value).byteLength > MAX_STRING_BYTES)
    return fail("unbounded_value", path);
  return { ok: true, value };
}

function safeIdentifier(value: unknown, path: string): VerificationError | undefined {
  if (typeof value !== "string") return { code: "invalid_value", path };
  const bounded = boundedString(value, path);
  if (!bounded.ok) return bounded.error;
  if (new TextEncoder().encode(bounded.value).byteLength > MAX_IDENTIFIER_BYTES)
    return { code: "unbounded_value", path };
  if (!/^[a-z][a-z0-9._-]{0,127}$/.test(bounded.value)) return { code: "invalid_value", path };
  return undefined;
}

function isSigningRole(value: unknown): value is SigningRole {
  return value === "release" || value === "promotion";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function validateJsonTree(value: unknown, path: string, depth = 0): VerificationResult<null> {
  if (typeof value === "string") {
    const bounded = boundedString(value, path);
    return bounded.ok ? { ok: true, value: null } : fail(bounded.error.code, bounded.error.path);
  }
  if (typeof value === "number")
    return Number.isSafeInteger(value) ? { ok: true, value: null } : fail("invalid_scalar", path);
  if (typeof value === "boolean" || value === null) return { ok: true, value: null };
  if (Array.isArray(value)) {
    if (depth >= MAX_DEPTH) return fail("unbounded_value", path);
    if (value.length > MAX_ARRAY_ITEMS) return fail("unbounded_value", path);
    for (let index = 0; index < value.length; index += 1) {
      const child = validateJsonTree(value[index], `${path}[${index}]`, depth + 1);
      if (!child.ok) return child;
    }
    return { ok: true, value: null };
  }
  if (!isRecord(value)) return fail("invalid_type", path);
  if (depth >= MAX_DEPTH) return fail("unbounded_value", path);
  if (Object.keys(value).length > MAX_OBJECT_MEMBERS) return fail("unbounded_value", path);
  for (const [key, childValue] of Object.entries(value).sort(([left], [right]) =>
    compareUtf8(left, right),
  )) {
    const keyResult = boundedString(key, `${path}.<key>`);
    if (!keyResult.ok) return keyResult;
    const childPath = `${path}.${key}`;
    const child =
      key === "payload" && typeof childValue === "string"
        ? new TextEncoder().encode(childValue).byteLength <= MAX_ENCODED_PAYLOAD_BYTES
          ? ({ ok: true, value: null } as const)
          : fail("unbounded_value", childPath)
        : validateJsonTree(childValue, childPath, depth + 1);
    if (!child.ok) return child;
  }
  return { ok: true, value: null };
}

function decodeUtf8(bytes: Uint8Array, path: string): VerificationResult<string> {
  try {
    return { ok: true, value: new TextDecoder("utf-8", { fatal: true }).decode(bytes) };
  } catch {
    return fail("invalid_utf8", path);
  }
}

function decodeBase64Url(
  value: unknown,
  path: string,
  maxEncodedBytes: number,
): VerificationResult<Uint8Array> {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxEncodedBytes ||
    !/^[A-Za-z0-9_-]+$/.test(value) ||
    value.length % 4 === 1
  )
    return fail("invalid_base64", path);
  try {
    const binary = atob(
      value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4),
    );
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    if (encodeBase64Url(bytes) !== value) return fail("invalid_base64", path);
    return { ok: true, value: bytes };
  } catch {
    return fail("invalid_base64", path);
  }
}

function encodeBase64Url(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function arrayBuffer(value: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(value.byteLength);
  new Uint8Array(buffer).set(value);
  return buffer;
}

async function digest(value: Uint8Array): Promise<string> {
  const bytes = new Uint8Array(
    await globalThis.crypto.subtle.digest("SHA-256", arrayBuffer(value)),
  );
  return `sha256:${[...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

function identityKey(value: CatalogIdentity | FirstPartyFrontendRelease): string {
  const identity =
    "application" in value && "package" in value && "surface" in value ? value : value;
  return [
    identity.application.id,
    identity.application.version,
    identity.package.id,
    identity.package.version,
    identity.surface.id,
    identity.surface.version,
  ].join("\u0000");
}

function uniqueName(
  names: Map<string, string>,
  name: string | undefined,
  identity: string,
  path: string,
): VerificationResult<Map<string, string>> {
  if (name === undefined) return { ok: true, value: names };
  const owner = names.get(name);
  if (owner !== undefined && owner !== identity)
    return fail("duplicate_remote_or_exposed_module", path);
  names.set(name, identity);
  return { ok: true, value: names };
}

function compareIdentity(left: CatalogIdentity, right: CatalogIdentity): number {
  for (const [a, b] of [
    [left.application.id, right.application.id],
    [left.application.version, right.application.version],
    [left.package.id, right.package.id],
    [left.package.version, right.package.version],
    [left.surface.id, right.surface.id],
    [left.surface.version, right.surface.version],
  ] as const) {
    const result =
      typeof a === "string" && typeof b === "string"
        ? compareUtf8(a, b)
        : a === b
          ? 0
          : a < b
            ? -1
            : 1;
    if (result !== 0) return result;
  }
  return 0;
}

function compareUtf8(left: string, right: string): number {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  const length = Math.min(a.length, b.length);
  for (let index = 0; index < length; index += 1)
    if (a[index] !== b[index]) return a[index]! < b[index]! ? -1 : 1;
  return a.length === b.length ? 0 : a.length < b.length ? -1 : 1;
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isRecord(value))
    return `{${Object.keys(value)
      .sort(compareUtf8)
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" && Number.isInteger(value)) return String(value);
  if (value === true) return "true";
  if (value === false) return "false";
  if (value === null) return "null";
  throw new Error("non-canonical scalar");
}

function preflightJson(text: string, path: string): VerificationResult<null> {
  let index = 0;
  const whitespace = (): void => {
    while (index < text.length && " \t\n\r".includes(text[index]!)) index += 1;
  };
  const stringToken = (
    stringPath: string,
    maxBytes = MAX_STRING_BYTES,
  ): VerificationResult<number> => {
    const start = index;
    if (text[index] !== '"') return fail("invalid_json", stringPath);
    index += 1;
    while (index < text.length) {
      const character = text[index]!;
      if (character === '"') {
        index += 1;
        if (new TextEncoder().encode(text.slice(start, index)).byteLength > maxBytes + 2)
          return fail("unbounded_value", stringPath);
        return { ok: true, value: index };
      }
      if (character === "\\") {
        index += 2;
        if (text[index - 1] === "u") index += 4;
      } else {
        if (character < " ") return fail("invalid_json", path);
        index += 1;
      }
    }
    return fail("invalid_json", stringPath);
  };
  const valueToken = (
    depth: number,
    valuePath: string,
    stringMax = MAX_STRING_BYTES,
  ): VerificationResult<number> => {
    whitespace();
    if (depth >= MAX_DEPTH && (text[index] === "{" || text[index] === "["))
      return fail("unbounded_value", valuePath);
    if (text[index] === '"') return stringToken(valuePath, stringMax);
    if (text[index] === "{") {
      index += 1;
      whitespace();
      const keys = new Set<string>();
      let count = 0;
      if (text[index] === "}") {
        index += 1;
        return { ok: true, value: index };
      }
      while (index < text.length) {
        if (++count > MAX_OBJECT_MEMBERS || text[index] !== '"')
          return fail(count > MAX_OBJECT_MEMBERS ? "unbounded_value" : "invalid_json", valuePath);
        const keyStart = index;
        const key = stringToken(path);
        if (!key.ok) return key;
        let decoded: unknown;
        try {
          decoded = JSON.parse(text.slice(keyStart, key.value)) as unknown;
        } catch {
          return fail("invalid_json", valuePath);
        }
        if (typeof decoded !== "string") return fail("invalid_json", valuePath);
        if (keys.has(decoded)) return fail("duplicate_json_key", `${valuePath}.${decoded}`);
        keys.add(decoded);
        whitespace();
        if (text[index] !== ":") return fail("invalid_json", valuePath);
        index += 1;
        const child = valueToken(
          depth + 1,
          `${valuePath}.${decoded}`,
          decoded === "payload" ? MAX_ENCODED_PAYLOAD_BYTES : MAX_STRING_BYTES,
        );
        if (!child.ok) return child;
        whitespace();
        if (text[index] === "}") {
          index += 1;
          return { ok: true, value: index };
        }
        if (text[index] !== ",") return fail("invalid_json", valuePath);
        index += 1;
        whitespace();
      }
      return fail("invalid_json", valuePath);
    }
    if (text[index] === "[") {
      index += 1;
      whitespace();
      let count = 0;
      if (text[index] === "]") {
        index += 1;
        return { ok: true, value: index };
      }
      while (index < text.length) {
        if (++count > MAX_ARRAY_ITEMS) return fail("unbounded_value", valuePath);
        const child = valueToken(depth + 1, `${valuePath}[${count - 1}]`);
        if (!child.ok) return child;
        whitespace();
        if (text[index] === "]") {
          index += 1;
          return { ok: true, value: index };
        }
        if (text[index] !== ",") return fail("invalid_json", valuePath);
        index += 1;
        whitespace();
      }
      return fail("invalid_json", valuePath);
    }
    if (text.startsWith("true", index)) {
      index += 4;
      return { ok: true, value: index };
    }
    if (text.startsWith("false", index)) {
      index += 5;
      return { ok: true, value: index };
    }
    if (text.startsWith("null", index)) {
      index += 4;
      return { ok: true, value: index };
    }
    const start = index;
    if (text[index] === "-") index += 1;
    const digitStart = index;
    while (index < text.length && /[0-9]/.test(text[index]!)) index += 1;
    if (index === digitStart) return fail("invalid_json", valuePath);
    if (text[index] === "." || text[index] === "e" || text[index] === "E")
      return fail("invalid_scalar", valuePath);
    if (index < text.length && !" \t\n\r,]}".includes(text[index]!))
      return fail("invalid_json", valuePath);
    if (text.slice(start, index).startsWith("-0") && index > start + 2)
      return fail("invalid_json", valuePath);
    const digits = text.slice(start, index).replace(/^-/, "").replace(/^0+/, "") || "0";
    if (digits.length > 16 || (digits.length === 16 && digits > "9007199254740991"))
      return fail("invalid_scalar", valuePath);
    return { ok: true, value: index };
  };
  const result = valueToken(0, path);
  if (!result.ok) return result;
  whitespace();
  return index === text.length ? { ok: true, value: null } : fail("invalid_json", path);
}

function fail<T>(code: VerificationErrorCode, path: string): VerificationResult<T> {
  return { ok: false, error: { code, path } };
}
function prefixError(error: VerificationError, prefix: string): VerificationError {
  return { code: error.code, path: error.path === "$" ? prefix : prefix + error.path.slice(1) };
}
