/// <reference types="node" />

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vite-plus/test";
import {
  FRONTEND_RELEASE_ALGORITHM,
  FRONTEND_RELEASE_PAYLOAD_ENCODING,
  SIGNED_FRONTEND_DOCUMENT_SCHEMA,
  verifyFirstPartyFrontendRelease,
  verifyFirstPartyFrontendReleaseCatalog,
  verifySignedFrontendDocument,
  type AcceptedCatalogState,
  type FrontendReleaseKeyRecords,
  type FrontendReleasePublicKey,
  type VerifyOptions,
  type SignedFrontendDocument,
  type VerificationErrorCode,
} from "./release-catalog";

type JsonRecord = Record<string, unknown>;
type CorpusEnvelope = { payload: string; envelope: SignedFrontendDocument };
type CorpusCase = {
  id: string;
  operation: "document" | "release" | "catalog";
  source: string;
  expected: JsonRecord;
  [key: string]: unknown;
};
type Corpus = {
  version: 2;
  origin: string;
  now: string;
  corpusSchema: "cadence.frontend-release-contract.adversarial.v2";
  unicodeCanonical: { value: string; canonical: string; bytes: number };
  keys: FrontendReleasePublicKey[];
  release: CorpusEnvelope;
  catalog: CorpusEnvelope;
  rolloutCatalog: CorpusEnvelope;
  rollbackCatalog: CorpusEnvelope;
  largeRelease: {
    artifactCount: number;
    pathPadding: number;
    payloadBytes: number;
    releaseId: string;
  };
  caseCount: number;
  maxCases: number;
  cases: CorpusCase[];
};

const corpus = JSON.parse(
  readFileSync(
    new URL("../../../../test/fixtures/frontend_release_catalog_v1.json", import.meta.url),
    "utf8",
  ),
) as Corpus;
const options = { now: corpus.now, allowedOrigins: [corpus.origin] };
const releaseSeed = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60";
const promotionSeed = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb";
const envelopeRequiredStringFields = [
  { key: "schema", wrongTypeCode: "invalid_type", expectedPath: "$.schema" },
  { key: "keyId", wrongTypeCode: "invalid_type", expectedPath: "$.keyId" },
  { key: "algorithm", wrongTypeCode: "invalid_type", expectedPath: "$.algorithm" },
  { key: "signingRole", wrongTypeCode: "invalid_role", expectedPath: "$.signingRole" },
  { key: "payloadEncoding", wrongTypeCode: "invalid_type", expectedPath: "$.payloadEncoding" },
  { key: "payload", wrongTypeCode: "invalid_base64", expectedPath: "$.payload" },
  { key: "signature", wrongTypeCode: "invalid_base64", expectedPath: "$.signature" },
] as const;

describe("signed first-party frontend release contracts", () => {
  it("accepts the shared exact-byte RFC8032 release and catalog fixtures", async () => {
    const unicode = corpus.unicodeCanonical;
    const unicodeCanonical = canonical({ value: unicode.value });
    expect(unicodeCanonical).toBe(unicode.canonical);
    expect(new TextEncoder().encode(unicodeCanonical).byteLength).toBe(unicode.bytes);

    const release = await verifyFirstPartyFrontendRelease(
      corpus.release.envelope,
      corpus.keys,
      options,
    );
    expect(release.ok).toBe(true);
    if (!release.ok) return;
    expect(release.value.release.releaseId).toBe(
      "sha256:1c1bd2f62ada2a7e6b9ab35f4e0f36d3bb4c46995221a1c5d7eb8f7f9f6a4470",
    );
    expect(new TextDecoder().decode(release.value.payloadBytes)).toBe(corpus.release.payload);

    const catalog = await verifyFirstPartyFrontendReleaseCatalog(
      corpus.catalog.envelope,
      corpus.keys,
      options,
    );
    expect(catalog.ok).toBe(true);
    if (!catalog.ok) return;
    expect(catalog.value.entries[0]?.current.releaseId).toBe(
      "sha256:8afe661d6cba541a26667f12b18bbc0ef527fe64181db127270dc54030c4acfa",
    );
    expect(catalog.value.entries[0]?.fallback?.releaseId).toBe(
      "sha256:1c1bd2f62ada2a7e6b9ab35f4e0f36d3bb4c46995221a1c5d7eb8f7f9f6a4470",
    );
    expect(catalog.value.acceptedState.digest).toBe(catalog.value.digest);
  });

  it("requires explicit verification time and keeps signed identities clock-independent", async () => {
    const missingReleaseNow = await verifyFirstPartyFrontendRelease(
      corpus.release.envelope,
      corpus.keys,
      { allowedOrigins: [corpus.origin] },
    );
    expect(missingReleaseNow).toEqual({
      ok: false,
      error: { code: "invalid_timestamp", path: "$.now" },
    });

    const missingCatalogNow = await verifyFirstPartyFrontendReleaseCatalog(
      corpus.catalog.envelope,
      corpus.keys,
      { allowedOrigins: [corpus.origin] },
    );
    expect(missingCatalogNow).toEqual({
      ok: false,
      error: { code: "invalid_timestamp", path: "$.now" },
    });

    const first = await verifyFirstPartyFrontendRelease(
      corpus.release.envelope,
      corpus.keys,
      options,
    );
    const second = await verifyFirstPartyFrontendRelease(corpus.release.envelope, corpus.keys, {
      ...options,
      now: "2026-08-30T18:31:00Z",
    });
    expect(first.ok).toBe(true);
    expect(second.ok).toBe(true);
    if (!first.ok || !second.ok) return;

    expect(second.value.release.releaseId).toBe(first.value.release.releaseId);
    expect(second.value.digest).toBe(first.value.digest);
    expect(second.value.payloadBytes).toEqual(first.value.payloadBytes);
    expect(second.value.keyId).toBe(first.value.keyId);
    expect(second.value.signingRole).toBe(first.value.signingRole);
  });

  it("rejects a pre-epoch Date verification clock while preserving valid Date clocks", async () => {
    const beforeEpoch = await verifyFirstPartyFrontendRelease(
      corpus.release.envelope,
      corpus.keys,
      { ...options, now: new Date(-1) },
    );
    expect(beforeEpoch).toEqual({
      ok: false,
      error: { code: "invalid_timestamp", path: "$.now" },
    });

    const validDate = await verifyFirstPartyFrontendRelease(corpus.release.envelope, corpus.keys, {
      ...options,
      now: new Date(Date.parse(corpus.now)),
    });
    expect(validDate.ok).toBe(true);
  });

  it("binds intentional release timestamp changes to the signed release identity", async () => {
    const release = JSON.parse(corpus.release.payload) as JsonRecord;
    const shifted = await withReleaseId({
      ...release,
      releasedAt: "2026-08-30T17:01:00Z",
    });

    expect(shifted.releaseId).not.toBe(release.releaseId);
    expect(shifted.application).toEqual(release.application);
    expect(shifted.package).toEqual(release.package);
    expect(shifted.surface).toEqual(release.surface);
    expect(shifted.artifacts).toEqual(release.artifacts);
  });

  it("consumes every bounded v2 adversarial case with the shared exact outcome", async () => {
    expect(corpus.version).toBe(2);
    expect(corpus.corpusSchema).toBe("cadence.frontend-release-contract.adversarial.v2");
    expect(corpus.caseCount).toBe(corpus.cases.length);
    expect(corpus.cases.length).toBeLessThanOrEqual(corpus.maxCases);
    expect(new Set(corpus.cases.map(({ id }) => id)).size).toBe(corpus.cases.length);

    const baseline = await verifyFirstPartyFrontendReleaseCatalog(
      corpus.catalog.envelope,
      corpus.keys,
      options,
    );
    expect(baseline.ok).toBe(true);
    if (!baseline.ok) return;

    for (const corpusCase of corpus.cases) {
      const actual = await runCorpusCase(corpusCase, baseline.value.acceptedState);
      expect(corpusProjection(actual, corpusCase.expected), corpusCase.id).toEqual(
        corpusCase.expected,
      );
    }
  });

  it("keeps every required envelope string field in the bounded type inventory", async () => {
    for (const field of envelopeRequiredStringFields) {
      const result = await verifySignedFrontendDocument(
        { ...corpus.release.envelope, [field.key]: 1 },
        corpus.keys,
        options,
      );
      expect(result).toEqual({
        ok: false,
        error: { code: field.wrongTypeCode, path: field.expectedPath },
      });
    }
  });

  it("admits replay, rollout, and a higher-sequence rollback swap", async () => {
    const first = await verifyFirstPartyFrontendReleaseCatalog(
      corpus.catalog.envelope,
      corpus.keys,
      options,
    );
    expect(first.ok).toBe(true);
    if (!first.ok) return;

    const replay = await verifyFirstPartyFrontendReleaseCatalog(
      corpus.catalog.envelope,
      corpus.keys,
      {
        ...options,
        acceptedState: first.value.acceptedState,
      },
    );
    expect(replay).toMatchObject({ ok: true, value: { acceptance: "identical" } });

    const successorOptions = {
      ...options,
      now: "2026-08-30T19:00:00Z",
      acceptedState: first.value.acceptedState,
    };
    expect(
      await verifyFirstPartyFrontendReleaseCatalog(
        corpus.rolloutCatalog.envelope,
        corpus.keys,
        successorOptions,
      ),
    ).toMatchObject({ ok: true, value: { acceptance: "new" } });
    const rollback = await verifyFirstPartyFrontendReleaseCatalog(
      corpus.rollbackCatalog.envelope,
      corpus.keys,
      successorOptions,
    );
    expect(rollback).toMatchObject({ ok: true, value: { acceptance: "new" } });
    if (rollback.ok)
      expect(rollback.value.entries[0]?.current.releaseId).toBe(
        first.value.entries[0]?.fallback?.releaseId,
      );

    const baseCatalog = JSON.parse(corpus.catalog.payload) as JsonRecord;
    const lower = await signedCatalog({ ...baseCatalog, sequence: 9 }, promotionSeed);
    await expectCode(
      verifyFirstPartyFrontendReleaseCatalog(lower, corpus.keys, successorOptions),
      "lower_sequence",
    );
    const fork = await signedCatalog(
      { ...baseCatalog, expiresAt: "2026-08-31T17:00:00Z" },
      promotionSeed,
    );
    await expectCode(
      verifyFirstPartyFrontendReleaseCatalog(fork, corpus.keys, {
        ...options,
        acceptedState: first.value.acceptedState,
      }),
      "same_sequence_fork",
    );
  });

  it("requires independent release-role signatures for nested values", async () => {
    const release = JSON.parse(corpus.release.payload) as JsonRecord;
    const forged = await signEnvelope(
      corpus.release.payload,
      "fixture-promotion-key",
      "release",
      promotionSeed,
    );
    const payload = canonical({
      schema: "cadence.first-party-frontend-release-catalog.v1",
      sequence: 20,
      publishedAt: "2026-08-30T19:00:00Z",
      expiresAt: "2026-08-31T18:00:00Z",
      entries: [{ identity: releaseIdentity(release), current: forged }],
    });
    await expectCode(
      verifyFirstPartyFrontendReleaseCatalog(
        await signEnvelope(payload, "fixture-promotion-key", "promotion", promotionSeed),
        corpus.keys,
        { ...options, now: "2026-08-30T19:00:00Z" },
      ),
      "role_not_allowed",
    );
  });

  it("binds role/schema and exact signed payload bytes", async () => {
    const role = { ...corpus.release.envelope, signingRole: "promotion" as const };
    await expectCode(
      verifySignedFrontendDocument(role, corpus.keys, options),
      "schema_role_mismatch",
    );
    const tamperedText = corpus.release.payload.replace("telemetry_decom", "telemetry_decomx");
    const tamperedPayload = {
      ...corpus.release.envelope,
      payload: encodeBase64(new TextEncoder().encode(tamperedText)),
    };
    await expectCode(
      verifySignedFrontendDocument(tamperedPayload, corpus.keys, options),
      "invalid_signature",
    );
    await expectCode(
      verifySignedFrontendDocument(
        { ...corpus.release.envelope, signature: "A" },
        corpus.keys,
        options,
      ),
      "invalid_base64",
    );
    await expectCode(
      verifyFirstPartyFrontendRelease(corpus.release.envelope, [], options),
      "unknown_key",
    );
  });

  it("enforces key lifecycle, trust-map binding, and malformed key/signature errors", async () => {
    const releaseKey = corpus.keys.find((key) => key.keyId === "fixture-release-key");
    expect(releaseKey).toBeDefined();
    if (!releaseKey) return;
    await expectCode(
      verifyFirstPartyFrontendRelease(
        corpus.release.envelope,
        [{ ...releaseKey, validFrom: "2026-08-31T00:00:00Z" }, corpus.keys[0]!],
        options,
      ),
      "not_yet_valid_key",
    );
    await expectCode(
      verifyFirstPartyFrontendRelease(
        corpus.release.envelope,
        [{ ...releaseKey, validUntil: "2026-08-30T18:30:00Z" }, corpus.keys[0]!],
        options,
      ),
      "expired_key",
    );
    await expectCode(
      verifyFirstPartyFrontendRelease(
        corpus.release.envelope,
        [{ ...releaseKey, revokedAt: corpus.now }, corpus.keys[0]!],
        options,
      ),
      "revoked_key",
    );
    await expectCode(
      verifyFirstPartyFrontendRelease(corpus.release.envelope, { wrong: releaseKey }, options),
      "invalid_key_record",
    );
    await expectCode(
      verifyFirstPartyFrontendRelease(
        corpus.release.envelope,
        [{ ...releaseKey, publicKey: "A" }, corpus.keys[0]!],
        options,
      ),
      "invalid_key_record",
    );
  });

  it("rejects canonicalization, contract, path, URL, and artifact mutations", async () => {
    const release = JSON.parse(corpus.release.payload) as JsonRecord;
    const reversed = await withReleaseId({
      ...release,
      artifacts: [...(release.artifacts as unknown[]).slice().reverse()],
    });
    await expectCode(
      verifyFirstPartyFrontendRelease(await signedRelease(reversed), corpus.keys, options),
      "unsorted_artifacts",
    );
    const mutable = await withReleaseId(release);
    mutable.artifactBaseUrl = "https://cdn.example.com/releases/telemetry_decom/current/artifacts/";
    await expectCode(
      verifyFirstPartyFrontendRelease(await signedRelease(mutable), corpus.keys, options),
      "invalid_base_url",
    );
    const circular = {
      ...release,
      artifactBaseUrl:
        "https://cdn.example.com/releases/telemetry_decom/sha256:0000000000000000000000000000000000000000000000000000000000000000/artifacts/",
    };
    await expectCode(
      verifyFirstPartyFrontendRelease(await signedRelease(circular), corpus.keys, options),
      "invalid_base_url",
    );
    const hostMismatch = await withReleaseId({
      ...release,
      hostCompatibility: { ...(release.hostCompatibility as JsonRecord), vueRange: "^3.4.0" },
    });
    await expectCode(
      verifyFirstPartyFrontendRelease(await signedRelease(hostMismatch), corpus.keys, options),
      "invalid_value",
    );
    await expectCode(
      verifySignedFrontendDocument(
        await signEnvelope(
          `${corpus.release.payload} `,
          "fixture-release-key",
          "release",
          releaseSeed,
        ),
        corpus.keys,
        options,
      ),
      "noncanonical_json",
    );
    await expectCode(
      verifySignedFrontendDocument(
        await signEnvelope(
          '{"schema":"cadence.first-party-frontend-release.v1","schema":"cadence.first-party-frontend-release.v1}',
          "fixture-release-key",
          "release",
          releaseSeed,
        ),
        corpus.keys,
        options,
      ),
      "duplicate_json_key",
    );
  });

  it("uses full versioned identity and catalog-wide name uniqueness", async () => {
    const release = JSON.parse(corpus.release.payload) as JsonRecord;
    const second = await withReleaseId({
      ...release,
      application: { ...(release.application as JsonRecord), id: "telemetry_z" },
    });
    const secondEnvelope = await signedRelease(second);
    const baseCatalog = JSON.parse(corpus.catalog.payload) as JsonRecord;
    const duplicateRemote = await signedCatalog(
      {
        ...baseCatalog,
        entries: [
          { identity: releaseIdentity(release), current: corpusCatalogCurrent() },
          { identity: releaseIdentity(second), current: secondEnvelope },
        ],
      },
      promotionSeed,
    );
    await expectCode(
      verifyFirstPartyFrontendReleaseCatalog(duplicateRemote, corpus.keys, options),
      "duplicate_remote_or_exposed_module",
    );
    const wrongIdentity = await signedCatalog(
      {
        ...baseCatalog,
        entries: [
          {
            identity: {
              ...(JSON.parse(JSON.stringify(releaseIdentity(release))) as JsonRecord),
              application: { id: "telemetry_decom", version: 2 },
            },
            current: corpus.release.envelope,
          },
        ],
      },
      promotionSeed,
    );
    await expectCode(
      verifyFirstPartyFrontendReleaseCatalog(wrongIdentity, corpus.keys, options),
      "identity_mismatch",
    );
  });

  it("keeps Unicode and the shared 600-kilobyte payload within byte bounds", async () => {
    const release = JSON.parse(corpus.release.payload) as JsonRecord;
    const unicode = await withReleaseId({
      ...release,
      provenance: { ...(release.provenance as JsonRecord), buildId: "é".repeat(256) },
    });
    expect(
      (await verifyFirstPartyFrontendRelease(await signedRelease(unicode), corpus.keys, options))
        .ok,
    ).toBe(true);
    const oversized = await withReleaseId({
      ...release,
      provenance: { ...(release.provenance as JsonRecord), buildId: "é".repeat(257) },
    });
    await expectCode(
      verifyFirstPartyFrontendRelease(await signedRelease(oversized), corpus.keys, options),
      "unbounded_value",
    );
    const artifacts = Array.from({ length: corpus.largeRelease.artifactCount }, (_, index) => ({
      path: `assets/${String(index).padStart(4, "0")}-${"x".repeat(corpus.largeRelease.pathPadding)}.js`,
      sha256: "e".repeat(64),
      size: 5000,
      mediaType: "application/javascript",
    }));
    const large = await withReleaseId({
      ...release,
      manifest: artifacts[0],
      artifacts,
      provenance: { ...(release.provenance as JsonRecord), buildId: "fixture-build-4" },
      releasedAt: "2026-08-30T17:45:00Z",
    });
    const largePayload = canonical(large);
    expect(new TextEncoder().encode(largePayload).byteLength).toBe(
      corpus.largeRelease.payloadBytes,
    );
    expect(large.releaseId).toBe(corpus.largeRelease.releaseId);
    expect(
      (
        await verifyFirstPartyFrontendRelease(
          await signEnvelope(largePayload, "fixture-release-key", "release", releaseSeed),
          corpus.keys,
          options,
        )
      ).ok,
    ).toBe(true);
  });

  it("turns unexpected untrusted-object exceptions into structured errors", async () => {
    const hostile = new Proxy(
      {},
      {
        ownKeys: () => {
          throw new Error("hostile");
        },
      },
    );
    expect(await verifySignedFrontendDocument(hostile, corpus.keys, options)).toEqual({
      ok: false,
      error: { code: "invalid_document", path: "$" },
    });
  });
});

function releaseIdentity(release: JsonRecord): JsonRecord {
  return { application: release.application, package: release.package, surface: release.surface };
}

type CorpusResult =
  | { ok: true; value: unknown }
  | { ok: false; error: { code: string; path: string } };

async function runCorpusCase(
  corpusCase: CorpusCase,
  baselineState: AcceptedCatalogState,
): Promise<CorpusResult> {
  const caseOptions: VerifyOptions = {
    now: typeof corpusCase.now === "string" ? corpusCase.now : corpus.now,
    allowedOrigins: Array.isArray(corpusCase.allowedOrigins)
      ? (corpusCase.allowedOrigins as string[])
      : [corpus.origin],
  };
  if (corpusCase.acceptedState === "catalog") {
    caseOptions.acceptedState = {
      ...baselineState,
      ...(typeof corpusCase.acceptedStatePublishedAt === "string"
        ? { publishedAt: corpusCase.acceptedStatePublishedAt }
        : {}),
    };
  }

  const document = await corpusDocument(corpusCase);
  const keys = corpusKeys(corpusCase);
  if (corpusCase.operation === "document")
    return verifySignedFrontendDocument(document, keys, caseOptions);
  if (corpusCase.operation === "release")
    return verifyFirstPartyFrontendRelease(document, keys, caseOptions);
  return verifyFirstPartyFrontendReleaseCatalog(document, keys, caseOptions);
}

async function corpusDocument(corpusCase: CorpusCase): Promise<unknown> {
  let document: unknown;
  switch (corpusCase.source) {
    case "release":
      document = corpus.release.envelope;
      break;
    case "catalog":
      document = corpus.catalog.envelope;
      break;
    case "rolloutCatalog":
      document = corpus.rolloutCatalog.envelope;
      break;
    case "rollbackCatalog":
      document = corpus.rollbackCatalog.envelope;
      break;
    case "release_payload": {
      let release = JSON.parse(corpus.release.payload) as JsonRecord;
      release = applyOperations(release, corpusCase.payloadPatches) as JsonRecord;
      if (corpusCase.recomputeReleaseId === true)
        release = await withReleaseId(release, corpusCase.preserveArtifactBaseUrl === true);
      document = await signEnvelope(
        canonical(release),
        "fixture-release-key",
        "release",
        releaseSeed,
      );
      break;
    }
    case "catalog_payload": {
      let payload = JSON.parse(corpus.catalog.payload) as JsonRecord;
      payload = applyOperations(payload, corpusCase.payloadPatches) as JsonRecord;
      document = await signEnvelope(
        canonical(payload),
        "fixture-promotion-key",
        "promotion",
        promotionSeed,
      );
      break;
    }
    case "generated":
      document = await generatedCorpusDocument(String(corpusCase.generated));
      break;
    default:
      throw new Error(`unknown corpus source: ${corpusCase.source}`);
  }

  if (typeof corpusCase.payloadText === "string")
    document = setEnvelopePayload(
      document,
      encodeBase64(new TextEncoder().encode(corpusCase.payloadText)),
    );
  if (corpusCase.payloadTextRef === "release-space")
    document = setEnvelopePayload(
      document,
      encodeBase64(new TextEncoder().encode(`${corpus.release.payload} `)),
    );
  if (typeof corpusCase.payloadBytesBase64 === "string")
    document = setEnvelopePayload(document, corpusCase.payloadBytesBase64);
  return applyOperations(document, corpusCase.envelopePatches);
}

function setEnvelopePayload(document: unknown, payload: string): unknown {
  if (!isRecord(document)) throw new Error("corpus envelope is not a record");
  return { ...document, payload };
}

function corpusKeys(corpusCase: CorpusCase): FrontendReleaseKeyRecords {
  if (corpusCase.keys === "empty") return [];
  if (corpusCase.keys === "wrong-trust-map") return { wrong: corpus.keys[0]! };
  if (corpusCase.keys === "duplicate") return [...corpus.keys, corpus.keys[1]!];
  return applyOperations(corpus.keys, corpusCase.keyPatches) as FrontendReleasePublicKey[];
}

async function generatedCorpusDocument(generated: string): Promise<SignedFrontendDocument> {
  if (generated === "depth") {
    const release = { ...JSON.parse(corpus.release.payload), x: nestedMap(16) } as JsonRecord;
    return signEnvelope(canonical(release), "fixture-release-key", "release", releaseSeed);
  }
  if (generated === "members") {
    const release = JSON.parse(corpus.release.payload) as JsonRecord;
    for (let index = 0; index <= 50; index += 1) release[`x${index}`] = 0;
    return signEnvelope(canonical(release), "fixture-release-key", "release", releaseSeed);
  }
  const release = JSON.parse(corpus.release.payload) as JsonRecord;
  if (generated === "duplicate-names") {
    const second = await withReleaseId({
      ...release,
      application: { ...(release.application as JsonRecord), id: "telemetry_z" },
    });
    const payload = canonical({
      schema: "cadence.first-party-frontend-release-catalog.v1",
      sequence: 20,
      publishedAt: "2026-08-30T19:00:00Z",
      expiresAt: "2026-08-31T18:00:00Z",
      entries: [
        { identity: releaseIdentity(release), current: await signedRelease(release) },
        { identity: releaseIdentity(second), current: await signedRelease(second) },
      ],
    });
    return signEnvelope(payload, "fixture-promotion-key", "promotion", promotionSeed);
  }
  if (generated === "duplicate-identity") {
    const signed = await signedRelease(release);
    const payload = canonical({
      schema: "cadence.first-party-frontend-release-catalog.v1",
      sequence: 20,
      publishedAt: "2026-08-30T19:00:00Z",
      expiresAt: "2026-08-31T18:00:00Z",
      entries: [
        { identity: releaseIdentity(release), current: signed },
        { identity: releaseIdentity(release), current: signed },
      ],
    });
    return signEnvelope(payload, "fixture-promotion-key", "promotion", promotionSeed);
  }
  throw new Error(`unknown generated corpus case: ${generated}`);
}

function nestedMap(levels: number): JsonRecord {
  return levels === 0 ? {} : { x: nestedMap(levels - 1) };
}

function applyOperations(value: unknown, operations: unknown): unknown {
  if (!Array.isArray(operations)) return value;
  return operations.reduce((current, operation) => {
    if (!isRecord(operation) || typeof operation.path !== "string")
      throw new Error("invalid corpus operation");
    const path = pointerPath(operation.path);
    const resolved = resolveCaseValue(operation.value);
    if (operation.op === "remove") return deletePointer(current, path);
    if (operation.op === "add" || operation.op === "replace")
      return putPointer(current, path, resolved);
    throw new Error(`unknown corpus operation: ${String(operation.op)}`);
  }, value);
}

function pointerPath(path: string): string[] {
  return path
    .replace(/^\//, "")
    .split("/")
    .filter((part) => part !== "")
    .map((part) => part.replace(/~1/g, "/").replace(/~0/g, "~"));
}

function putPointer(value: unknown, path: string[], replacement: unknown): unknown {
  const [head, ...tail] = path;
  if (head === undefined) return replacement;
  if (Array.isArray(value)) {
    const index = Number(head);
    const copy = [...value];
    copy[index] = tail.length === 0 ? replacement : putPointer(copy[index], tail, replacement);
    return copy;
  }
  if (!isRecord(value)) throw new Error("corpus pointer parent is not a record");
  return {
    ...value,
    [head]: tail.length === 0 ? replacement : putPointer(value[head], tail, replacement),
  };
}

function deletePointer(value: unknown, path: string[]): unknown {
  const [head, ...tail] = path;
  if (head === undefined) return value;
  if (Array.isArray(value)) {
    const index = Number(head);
    if (tail.length === 0) return value.filter((_item, itemIndex) => itemIndex !== index);
    const copy = [...value];
    copy[index] = deletePointer(copy[index], tail);
    return copy;
  }
  if (!isRecord(value)) throw new Error("corpus pointer parent is not a record");
  if (tail.length === 0) {
    const copy = { ...value };
    delete copy[head];
    return copy;
  }
  return { ...value, [head]: deletePointer(value[head], tail) };
}

function resolveCaseValue(value: unknown): unknown {
  if (!isRecord(value)) return value;
  if (isRecord(value.$repeat)) {
    const repeated = value.$repeat;
    if (typeof repeated.value !== "string" || typeof repeated.count !== "number")
      throw new Error("invalid repeat fixture");
    return repeated.value.repeat(repeated.count);
  }
  if (typeof value.$artifacts === "number") return generatedArtifacts(value.$artifacts);
  return value;
}

function generatedArtifacts(count: number): JsonRecord[] {
  return Array.from({ length: count }, (_unused, index) => ({
    path: `assets/${String(index).padStart(4, "0")}.js`,
    sha256: "e".repeat(64),
    size: 5000,
    mediaType: "application/javascript",
  }));
}

function corpusProjection(actual: CorpusResult, expected: JsonRecord): JsonRecord {
  if (actual.ok) {
    return expected.acceptance === undefined
      ? { ok: true }
      : { ok: true, acceptance: (actual.value as { acceptance: string }).acceptance };
  }
  return { ok: false, error: actual.error };
}

function corpusCatalogCurrent(): SignedFrontendDocument {
  const payload = JSON.parse(corpus.catalog.payload) as JsonRecord;
  return (payload.entries as JsonRecord[])[0]!.current as SignedFrontendDocument;
}

async function signedRelease(release: JsonRecord): Promise<SignedFrontendDocument> {
  return signEnvelope(canonical(release), "fixture-release-key", "release", releaseSeed);
}

async function signedCatalog(payload: JsonRecord, seed: string): Promise<SignedFrontendDocument> {
  return signEnvelope(canonical(payload), "fixture-promotion-key", "promotion", seed);
}

async function withReleaseId(
  release: JsonRecord,
  preserveArtifactBaseUrl = false,
): Promise<JsonRecord> {
  const logical = { ...release };
  delete logical.releaseId;
  delete logical.artifactBaseUrl;
  const releaseId = await digest(new TextEncoder().encode(canonical(logical)));
  const application = release.application as JsonRecord;
  if (typeof application.id !== "string") throw new Error("invalid application identity");
  return {
    ...release,
    releaseId,
    ...(preserveArtifactBaseUrl
      ? {}
      : {
          artifactBaseUrl: `https://cdn.example.com/releases/${application.id}/${releaseId}/artifacts/`,
        }),
  };
}

async function signEnvelope(
  payload: string,
  keyId: string,
  signingRole: "release" | "promotion",
  seedHex: string,
): Promise<SignedFrontendDocument> {
  const key = await globalThis.crypto.subtle.importKey(
    "pkcs8",
    arrayBuffer(
      new Uint8Array([
        0x30,
        0x2e,
        0x02,
        0x01,
        0x00,
        0x30,
        0x05,
        0x06,
        0x03,
        0x2b,
        0x65,
        0x70,
        0x04,
        0x22,
        0x04,
        0x20,
        ...hex(seedHex),
      ]),
    ),
    { name: "Ed25519" },
    false,
    ["sign"],
  );
  const payloadBytes = new TextEncoder().encode(payload);
  const signature = new Uint8Array(
    await globalThis.crypto.subtle.sign("Ed25519", key, arrayBuffer(payloadBytes)),
  );
  return {
    schema: SIGNED_FRONTEND_DOCUMENT_SCHEMA,
    keyId,
    algorithm: FRONTEND_RELEASE_ALGORITHM,
    signingRole,
    payloadEncoding: FRONTEND_RELEASE_PAYLOAD_ENCODING,
    payload: encodeBase64(payloadBytes),
    signature: encodeBase64(signature),
  };
}

async function digest(value: Uint8Array): Promise<string> {
  const hash = new Uint8Array(await globalThis.crypto.subtle.digest("SHA-256", arrayBuffer(value)));
  return `sha256:${[...hash].map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

async function expectCode(
  result: Promise<{ ok: boolean; error?: { code: VerificationErrorCode } }>,
  code: VerificationErrorCode,
): Promise<void> {
  expect(await result).toMatchObject({ ok: false, error: { code } });
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (isRecord(value))
    return `{${Object.keys(value)
      .sort(compareUtf8)
      .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
      .join(",")}}`;
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" && Number.isSafeInteger(value)) return String(value);
  if (value === true) return "true";
  if (value === false) return "false";
  if (value === null) return "null";
  throw new Error("invalid scalar");
}

function compareUtf8(left: string, right: string): number {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  for (let index = 0; index < Math.min(a.length, b.length); index += 1)
    if (a[index] !== b[index]) return a[index]! < b[index]! ? -1 : 1;
  return a.length - b.length;
}

function isRecord(value: unknown): value is JsonRecord {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hex(value: string): Uint8Array {
  return Uint8Array.from(value.match(/.{2}/g) ?? [], (pair) => Number.parseInt(pair, 16));
}

function arrayBuffer(value: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(value.byteLength);
  new Uint8Array(buffer).set(value);
  return buffer;
}

function encodeBase64(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
