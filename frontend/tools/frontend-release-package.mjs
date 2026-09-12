#!/usr/bin/env node

import { createHash, createPrivateKey, randomUUID, sign } from "node:crypto";
import { constants as fsConstants, readFile as readDescriptor } from "node:fs";
import { lstat, mkdir, open, readdir, realpath, rename, rm, rmdir } from "node:fs/promises";
import { basename, dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertReleaseArtifactPath,
  validateReleaseOutput,
} from "./frontend-release-output-check.mjs";

/** @typedef {Record<string, unknown>} Metadata */
/** @typedef {{path:string, sha256:string, size:number, mediaType:string, bytes:Buffer}} Artifact */
/** @typedef {{root:string, artifacts:readonly Readonly<Artifact>[]}} Inventory */
/** @typedef {{privateKeyFile?:string, privateKeyFd?:string|number, privateKeyEnv?:string}} KeySource */
/** @typedef {{inputDirectory:string, metadata:unknown, artifactOrigin:string, keyId:string, privateKey:import("node:crypto").KeyObject, afterSnapshot?:((root:string)=>void|Promise<void>) | undefined}} BuildOptions */
/** @typedef {BuildOptions & {outputDirectory:string}} PackageOptions */
/** @typedef {{inputDirectory:string, metadataFile:string, artifactOrigin:string, keyId:string, outputDirectory:string} & KeySource} CliOptions */

const TOOL_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(TOOL_DIRECTORY, "../..");

const ENVELOPE_SCHEMA = "cadence.signed-frontend-document.v1";
const RELEASE_SCHEMA = "cadence.first-party-frontend-release.v1";
const ALGORITHM = "ed25519";
const PAYLOAD_ENCODING = "base64url-json";
const HOST_CONTRACT = "cadence.application-host.v1";
const VUE_RANGE = "^3.5.40";
const MAX_ARTIFACT_SIZE = 100_000_000;
const MAX_TOTAL_ARTIFACT_SIZE = 100_000_000;
const MAX_ARTIFACTS = 2_048;
const MAX_PAYLOAD_BYTES = 750_000;
const MAX_DOCUMENT_BYTES = 1_000_000;
const MAX_ENCODED_PAYLOAD_BYTES = 1_000_004;
const MAX_ARTIFACT_PATH_BYTES = 256;
const MAX_STRING_BYTES = 512;
const MAX_IDENTIFIER_BYTES = 128;
const MAX_VERSION = 1_000;
const MAX_ACTIONS = 4_096;

const RELEASE_FIELDS = [
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
];

const METADATA_FIELDS = [
  "application",
  "package",
  "surface",
  "query",
  "actions",
  "remote",
  "module",
  "hostCompatibility",
  "provenance",
  "releasedAt",
];

const PRIVATE_KEY_ENV = "CADENCE_RELEASE_PRIVATE_KEY";
const RAW_ED25519_PKCS8_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");

const MEDIA_TYPES = new Map([
  [".avif", "image/avif"],
  [".css", "text/css"],
  [".gif", "image/gif"],
  [".html", "text/html"],
  [".ico", "image/x-icon"],
  [".jpeg", "image/jpeg"],
  [".jpg", "image/jpeg"],
  [".js", "application/javascript"],
  [".json", "application/json"],
  [".map", "application/json"],
  [".mjs", "application/javascript"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".txt", "text/plain"],
  [".wasm", "application/wasm"],
  [".webmanifest", "application/manifest+json"],
  [".webp", "image/webp"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

class ReleasePackagerError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "ReleasePackagerError";
  }
}

/** @param {string} message @returns {never} */

function fail(message) {
  throw new ReleasePackagerError(message);
}

/** @param {string} left @param {string} right */

function compareUtf8(left, right) {
  return Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"));
}

/** @param {unknown} value @returns {value is Metadata} */

function isPlainRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** @param {unknown} value @param {string[]} required @param {string} label @returns {asserts value is Metadata} */

function exactFields(value, required, label) {
  if (!isPlainRecord(value)) fail(`${label} must be an object`);
  const actual = Object.keys(value);
  const allowed = new Set(required);
  if (actual.length !== required.length || actual.some((key) => !allowed.has(key))) {
    fail(`${label} has an unexpected or missing field`);
  }
}

/** @param {unknown} value @param {string} label @param {{maxBytes?:number,nonEmpty?:boolean}} [options] */

function requireString(value, label, { maxBytes = MAX_STRING_BYTES, nonEmpty = false } = {}) {
  if (typeof value !== "string") fail(`${label} must be a string`);
  if (nonEmpty && value.length === 0) fail(`${label} must not be empty`);
  const bytes = Buffer.from(value, "utf8");
  if (bytes.byteLength > maxBytes) fail(`${label} is too large`);
  try {
    if (new TextDecoder("utf-8", { fatal: true }).decode(bytes) !== value) {
      fail(`${label} is not valid UTF-8`);
    }
  } catch {
    fail(`${label} is not valid UTF-8`);
  }
  return value;
}

/** @param {unknown} input @param {string} label */

function requireIdentifier(input, label) {
  const value = requireString(input, label, { maxBytes: MAX_IDENTIFIER_BYTES, nonEmpty: true });
  if (!/^[a-z][a-z0-9._-]{0,127}$/.test(value)) fail(`${label} is not a safe identifier`);
  return value;
}

/** @param {unknown} value @param {string} label */

function requireVersion(value, label) {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 1 ||
    value > MAX_VERSION
  ) {
    fail(`${label} is not a valid version`);
  }
  return value;
}

/** @param {unknown} value @param {string} label */

function requireIdentity(value, label) {
  exactFields(value, ["id", "version"], label);
  return {
    id: requireIdentifier(value.id, `${label}.id`),
    version: requireVersion(value.version, `${label}.version`),
  };
}

/** @param {unknown} input @param {string} label */

function requireTimestamp(input, label) {
  const value = requireString(input, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)) {
    fail(`${label} is not a canonical UTC timestamp`);
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds) || new Date(milliseconds).getUTCFullYear() < 1970) {
    fail(`${label} is not a valid timestamp`);
  }
  const canonical = new Date(milliseconds).toISOString();
  const expected = value.includes(".") ? value : value.replace("Z", ".000Z");
  if (canonical !== expected) fail(`${label} is not a valid timestamp`);
  return value;
}

/** @param {unknown} input @param {string} label @param {{originOnly?:boolean}} [options] */

function strictHttpsUrl(input, label, { originOnly = false } = {}) {
  const value = requireString(input, label);
  if (
    // oxlint-disable-next-line typescript/no-misused-spread -- Inspect code points only to reject ASCII control and space characters.
    [...value].some((character) => character.charCodeAt(0) <= 0x20) ||
    value.includes("\\") ||
    value.includes("%") ||
    value.includes("?") ||
    value.includes("#") ||
    !value.startsWith("https://")
  ) {
    fail(`${label} is not a valid HTTPS URL`);
  }

  const rest = value.slice("https://".length);
  const slash = rest.indexOf("/");
  const authority = slash === -1 ? rest : rest.slice(0, slash);
  const path = slash === -1 ? "" : rest.slice(slash);
  const match =
    /^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)(?::([1-9][0-9]{0,4}))?$/.exec(
      authority,
    );
  if (
    !match ||
    (match[2] !== undefined && (Number(match[2]) > 65_535 || Number(match[2]) === 443))
  ) {
    fail(`${label} is not a valid HTTPS authority`);
  }
  if (originOnly && path !== "") fail(`${label} must be an origin without a path`);
  if (!originOnly && path !== "" && !path.startsWith("/")) {
    fail(`${label} is not a valid HTTPS path`);
  }
  return { origin: `https://${authority}`, path };
}

/** @param {unknown} input @param {string} [label] */

function validateRelativeArtifactPath(input, label = "artifact path") {
  const value = requireString(input, label, { maxBytes: MAX_ARTIFACT_PATH_BYTES, nonEmpty: true });
  if (value.startsWith("/") || /^[A-Za-z]:/.test(value)) fail(`${label} must be relative`);
  if (value.includes("\\") || value.includes("\0")) fail(`${label} contains a forbidden separator`);
  const parts = value.split("/");
  if (parts.some((part) => part === "" || part === "." || part === "..")) {
    fail(`${label} contains traversal or an empty path component`);
  }
  const normalized = parts.join("/");
  if (normalized !== value) fail(`${label} is not normalized`);
  return value;
}

/** @param {string} root @param {string} candidate */

function isWithin(root, candidate) {
  const remainder = relative(root, candidate);
  return (
    remainder === "" ||
    (!remainder.startsWith(`..${sep}`) && remainder !== ".." && !isAbsolute(remainder))
  );
}

/** @param {string} left @param {string} right */

function pathsOverlap(left, right) {
  return isWithin(left, right) || isWithin(right, left);
}

/** @param {string} path */

function mediaTypeForPath(path) {
  const extension = extname(path).toLowerCase();
  const mediaType = MEDIA_TYPES.get(extension) ?? "application/octet-stream";
  if (
    !/^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/.test(
      mediaType,
    )
  ) {
    fail(`media type for ${path} is invalid`);
  }
  return mediaType;
}

/** @type {(keyof import("node:fs").BigIntStats)[]} */
const stableFileMetadata = [
  "dev",
  "ino",
  "mode",
  "nlink",
  "uid",
  "gid",
  "rdev",
  "size",
  "blksize",
  "blocks",
  "mtimeNs",
  "ctimeNs",
  "birthtimeNs",
];

/** @param {import("node:fs").BigIntStats} stats */

function fileMetadata(stats) {
  return stableFileMetadata.map((key) => [key, stats[key]?.toString() ?? null]);
}

/** @param {import("node:fs").BigIntStats} expected @param {import("node:fs").BigIntStats} actual @param {string} label */

function assertStableFileMetadata(expected, actual, label) {
  if (JSON.stringify(fileMetadata(expected)) !== JSON.stringify(fileMetadata(actual))) {
    fail(`${label} changed while it was read`);
  }
}

/** @param {string} filePath @param {string} label @param {import("node:fs").BigIntStats} expectedStats @param {number} [maxSize] */

async function readRegularFile(filePath, label, expectedStats, maxSize = MAX_ARTIFACT_SIZE) {
  const noFollow = fsConstants.O_NOFOLLOW ?? 0;
  let handle;
  try {
    handle = await open(filePath, fsConstants.O_RDONLY | noFollow);
    const stats = await handle.stat({ bigint: true });
    assertStableFileMetadata(expectedStats, stats, label);
    if (!stats.isFile()) fail(`${label} is not a regular file`);
    if (stats.size > BigInt(maxSize)) fail(`${label} is too large`);
    const bytes = await handle.readFile();
    if (BigInt(bytes.byteLength) !== stats.size) fail(`${label} changed while it was read`);
    const afterReadStats = await handle.stat({ bigint: true });
    assertStableFileMetadata(stats, afterReadStats, label);
    return bytes;
  } catch (error) {
    if (error instanceof ReleasePackagerError) throw error;
    fail(`${label} could not be read`);
  } finally {
    await handle?.close().catch(() => {});
  }
}

/** @param {string} inputDirectory */

async function enumerateArtifacts(inputDirectory) {
  const inputStats = await lstat(inputDirectory, { bigint: true }).catch(() =>
    fail("input directory does not exist"),
  );
  if (inputStats.isSymbolicLink()) fail("input directory must not be a symlink");
  if (!inputStats.isDirectory()) fail("input path must be a directory");
  const root = await realpath(inputDirectory).catch(() => fail("input directory does not exist"));
  const rootStats = await lstat(root, { bigint: true });
  assertStableFileMetadata(inputStats, rootStats, "input directory");
  if (!rootStats.isDirectory()) fail("input path must be a directory");

  /** @type {Artifact[]} */
  const artifacts = [];
  const paths = new Set();

  /** @param {string} directory @returns {Promise<void>} */

  async function visit(directory) {
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true, encoding: "utf8" });
    } catch {
      fail(`could not enumerate ${relative(root, directory) || "."}`);
    }
    entries.sort((left, right) => compareUtf8(left.name, right.name));

    for (const entry of entries) {
      const absolutePath = join(directory, entry.name);
      const relativePath = relative(root, absolutePath).split(sep).join("/");
      validateRelativeArtifactPath(relativePath, `artifact ${relativePath}`);
      if (!isWithin(root, absolutePath)) fail(`artifact ${relativePath} escapes the input root`);
      if (entry.isSymbolicLink()) fail(`artifact ${relativePath} is a symlink`);

      const stats = await lstat(absolutePath, { bigint: true }).catch(() =>
        fail(`artifact ${relativePath} disappeared`),
      );
      if (stats.isDirectory()) {
        if (relativePath !== "assets") {
          fail(`input tree contains an unexpected or nested directory ${relativePath}`);
        }
        await visit(absolutePath);
        continue;
      }
      if (!stats.isFile()) fail(`artifact ${relativePath} is not a regular file`);
      assertReleaseArtifactPath(relativePath);

      const resolvedPath = await realpath(absolutePath).catch(() =>
        fail(`artifact ${relativePath} is unreadable`),
      );
      if (!isWithin(root, resolvedPath)) fail(`artifact ${relativePath} escapes the input root`);
      const resolvedStats = await lstat(resolvedPath, { bigint: true }).catch(() =>
        fail(`artifact ${relativePath} disappeared`),
      );
      assertStableFileMetadata(stats, resolvedStats, `artifact ${relativePath}`);
      const bytes = await readRegularFile(absolutePath, `artifact ${relativePath}`, resolvedStats);
      const digest = createHash("sha256").update(bytes).digest("hex");
      if (paths.has(relativePath)) fail(`duplicate normalized artifact path ${relativePath}`);
      if (artifacts.length >= MAX_ARTIFACTS) fail("artifact inventory exceeds the count limit");
      paths.add(relativePath);
      artifacts.push({
        path: relativePath,
        sha256: digest,
        size: bytes.byteLength,
        mediaType: mediaTypeForPath(relativePath),
        bytes,
      });
    }
  }

  await visit(root);
  artifacts.sort((left, right) => compareUtf8(left.path, right.path));
  if (artifacts.length > MAX_ARTIFACTS) fail("artifact inventory exceeds the count limit");
  if (!artifacts.some(({ path }) => path === "mf-manifest.json")) {
    fail("input tree is missing required mf-manifest.json");
  }
  if (!artifacts.some(({ path }) => path === "remoteEntry.js")) {
    fail("input tree is missing required remoteEntry.js");
  }
  const totalSize = artifacts.reduce((total, artifact) => total + artifact.size, 0);
  if (totalSize > MAX_TOTAL_ARTIFACT_SIZE) fail("artifact inventory exceeds the total byte limit");
  return { root, artifacts };
}

/** @param {Inventory} inventory */

function freezeArtifactSnapshot(inventory) {
  const artifacts = inventory.artifacts.map((artifact) =>
    Object.freeze({ ...artifact, bytes: Buffer.from(artifact.bytes) }),
  );
  return Object.freeze({ root: inventory.root, artifacts: Object.freeze(artifacts) });
}

/** @param {unknown} metadata */

function validateMetadata(metadata) {
  exactFields(metadata, METADATA_FIELDS, "release metadata");
  const application = requireIdentity(metadata.application, "application");
  const packageIdentity = requireIdentity(metadata.package, "package");
  const surface = requireIdentity(metadata.surface, "surface");
  const query = requireIdentity(metadata.query, "query");

  if (!Array.isArray(metadata.actions) || metadata.actions.length > MAX_ACTIONS) {
    fail("actions must be a bounded array");
  }
  const actions = metadata.actions.map((action, index) =>
    requireString(action, `actions[${index}]`, { nonEmpty: true }),
  );
  if (new Set(actions).size !== actions.length) fail("actions must be unique");

  exactFields(metadata.remote, ["name"], "remote");
  const remoteName = requireIdentifier(metadata.remote.name, "remote.name");
  exactFields(metadata.module, ["exposedModule"], "module");
  const exposedModule = requireString(metadata.module.exposedModule, "module.exposedModule", {
    nonEmpty: true,
  });
  if (!/^\.[/][A-Za-z][A-Za-z0-9._-]{0,127}$/.test(exposedModule)) {
    fail("module.exposedModule is not a supported exposed module");
  }

  exactFields(
    metadata.hostCompatibility,
    ["hostContract", "compatibility", "vueRange"],
    "hostCompatibility",
  );
  if (metadata.hostCompatibility.hostContract !== HOST_CONTRACT) {
    fail("hostCompatibility.hostContract is not supported");
  }
  exactFields(
    metadata.hostCompatibility.compatibility,
    [
      "cadenceApplicationContract",
      "cadenceSurfaceContract",
      "cadenceFederatedRendererContract",
      "cadenceThemeContract",
    ],
    "hostCompatibility.compatibility",
  );
  for (const key of Object.keys(metadata.hostCompatibility.compatibility)) {
    if (metadata.hostCompatibility.compatibility[key] !== 1) {
      fail(`hostCompatibility.compatibility.${key} is not supported`);
    }
  }
  if (metadata.hostCompatibility.vueRange !== VUE_RANGE)
    fail("hostCompatibility.vueRange is not supported");

  exactFields(
    metadata.provenance,
    ["sourceRepository", "sourceRevision", "buildId", "builder", "workflow", "builtAt"],
    "provenance",
  );
  const sourceRepository = requireString(
    metadata.provenance.sourceRepository,
    "provenance.sourceRepository",
  );
  strictHttpsUrl(sourceRepository, "provenance.sourceRepository");
  const sourceRevision = requireString(
    metadata.provenance.sourceRevision,
    "provenance.sourceRevision",
    {
      nonEmpty: true,
    },
  );
  if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(sourceRevision)) {
    fail("provenance.sourceRevision must be a lowercase Git revision");
  }
  const buildId = requireString(metadata.provenance.buildId, "provenance.buildId");
  const builder = requireString(metadata.provenance.builder, "provenance.builder");
  const workflow = requireString(metadata.provenance.workflow, "provenance.workflow");
  const builtAt = requireTimestamp(metadata.provenance.builtAt, "provenance.builtAt");
  const releasedAt = requireTimestamp(metadata.releasedAt, "releasedAt");

  return {
    application,
    package: packageIdentity,
    surface,
    query,
    actions,
    remoteName,
    exposedModule,
    hostCompatibility: {
      hostContract: HOST_CONTRACT,
      compatibility: {
        cadenceApplicationContract: 1,
        cadenceSurfaceContract: 1,
        cadenceFederatedRendererContract: 1,
        cadenceThemeContract: 1,
      },
      vueRange: VUE_RANGE,
    },
    provenance: {
      sourceRepository,
      sourceRevision,
      buildId,
      builder,
      workflow,
      builtAt,
    },
    releasedAt,
  };
}

/** @param {{inventory:unknown,metadata:unknown,artifactOrigin:unknown}} options */

function buildReleasePayload({ inventory, metadata, artifactOrigin }) {
  if (!isPlainRecord(inventory) || !Array.isArray(inventory.artifacts))
    fail("artifact inventory is required");
  const normalizedMetadata = validateMetadata(metadata);
  const { origin } = strictHttpsUrl(artifactOrigin, "artifact origin", { originOnly: true });
  const paths = new Set();
  const artifacts = inventory.artifacts.map((artifact) => {
    if (!isPlainRecord(artifact)) fail("artifact inventory entry must be an object");
    const path = validateRelativeArtifactPath(artifact.path);
    if (paths.has(path)) fail(`duplicate normalized artifact path ${path}`);
    paths.add(path);
    if (typeof artifact.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(artifact.sha256)) {
      fail(`invalid digest for ${path}`);
    }
    if (
      typeof artifact.size !== "number" ||
      !Number.isSafeInteger(artifact.size) ||
      artifact.size < 0 ||
      artifact.size > MAX_ARTIFACT_SIZE
    ) {
      fail(`invalid size for ${path}`);
    }
    if (typeof artifact.mediaType !== "string" || mediaTypeForPath(path) !== artifact.mediaType) {
      fail(`invalid media type for ${path}`);
    }
    if (!Buffer.isBuffer(artifact.bytes)) {
      fail(`artifact bytes are missing for ${path}`);
    }
    if (artifact.bytes.byteLength !== artifact.size) {
      fail(`artifact size does not match bytes for ${path}`);
    }
    if (sha256Digest(artifact.bytes) !== `sha256:${artifact.sha256}`) {
      fail(`artifact digest does not match bytes for ${path}`);
    }
    return {
      path,
      sha256: artifact.sha256,
      size: artifact.size,
      mediaType: artifact.mediaType,
    };
  });
  if (artifacts.length === 0 || artifacts.length > MAX_ARTIFACTS) {
    fail("artifact inventory has an invalid count");
  }
  artifacts.sort((left, right) => compareUtf8(left.path, right.path));
  const manifest = artifacts.find(({ path }) => path === "mf-manifest.json");
  if (!manifest) fail("artifact inventory is missing mf-manifest.json");

  const logicalRelease = {
    schema: RELEASE_SCHEMA,
    application: normalizedMetadata.application,
    package: normalizedMetadata.package,
    surface: normalizedMetadata.surface,
    transport: "module_federation",
    remoteName: normalizedMetadata.remoteName,
    exposedModule: normalizedMetadata.exposedModule,
    manifest,
    artifacts,
    hostCompatibility: normalizedMetadata.hostCompatibility,
    provenance: normalizedMetadata.provenance,
    releasedAt: normalizedMetadata.releasedAt,
  };
  const releaseId = sha256Digest(Buffer.from(canonicalJson(logicalRelease), "utf8"));
  const release = {
    ...logicalRelease,
    releaseId,
    artifactBaseUrl: `${origin}/releases/${normalizedMetadata.application.id}/${releaseId}/artifacts/`,
  };
  if (Object.keys(release).sort().join("\0") !== RELEASE_FIELDS.slice().sort().join("\0")) {
    fail("internal release payload shape drifted from the server contract");
  }
  const payloadBytes = Buffer.from(canonicalJson(release), "utf8");
  if (payloadBytes.byteLength > MAX_PAYLOAD_BYTES) fail("release payload exceeds the byte limit");
  return {
    release,
    releaseId,
    payloadBytes,
    metadata: normalizedMetadata,
  };
}

/** @param {unknown} value @returns {string} */

function canonicalJson(value) {
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) fail("canonical JSON only supports safe integer values");
    return String(value);
  }
  if (Array.isArray(value)) {
    return `[${value
      .map((item, index) => {
        if (!Object.hasOwn(value, index)) fail("canonical JSON received a sparse array");
        return canonicalJson(item);
      })
      .join(",")}]`;
  }
  if (isPlainRecord(value)) {
    const keys = Object.keys(value).sort(compareUtf8);
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  fail("canonical JSON received an unsupported value");
}

/** @param {Buffer} bytes */

function sha256Digest(bytes) {
  return `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
}

/** @param {Buffer} bytes */

function base64Url(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

/** @param {{payloadBytes:Buffer,keyId:string,privateKey:import("node:crypto").KeyObject}} options */

function createSignedEnvelope({ payloadBytes, keyId, privateKey }) {
  requireIdentifier(keyId, "keyId");
  if (!Buffer.isBuffer(payloadBytes) || payloadBytes.byteLength > MAX_PAYLOAD_BYTES) {
    fail("release payload exceeds the byte limit");
  }
  const payload = base64Url(payloadBytes);
  if (payload.length > MAX_ENCODED_PAYLOAD_BYTES)
    fail("encoded release payload exceeds the byte limit");
  const signature = sign(null, payloadBytes, privateKey);
  const envelope = {
    schema: ENVELOPE_SCHEMA,
    keyId,
    algorithm: ALGORITHM,
    signingRole: "release",
    payloadEncoding: PAYLOAD_ENCODING,
    payload,
    signature: base64Url(signature),
  };
  const documentBytes = Buffer.from(canonicalJson(envelope), "utf8");
  if (documentBytes.byteLength > MAX_DOCUMENT_BYTES)
    fail("signed release document exceeds the byte limit");
  return { envelope, documentBytes };
}

/** @param {string} text */

function decodePrivateKeyText(text) {
  const trimmed = text.trim();
  if (trimmed.startsWith("-----BEGIN")) return Buffer.from(text, "utf8");
  if (/^[0-9a-fA-F]{64}$/.test(trimmed)) return Buffer.from(trimmed, "hex");
  if (/^[A-Za-z0-9_-]{43}$/.test(trimmed)) return Buffer.from(trimmed, "base64url");
  fail("private key material has an unsupported encoding");
}

/** @param {Buffer} bytes */

function privateKeyFromBytes(bytes) {
  /** @type {import("node:crypto").PrivateKeyInput} */
  const keyInput =
    bytes.length === 32
      ? {
          key: Buffer.concat([RAW_ED25519_PKCS8_PREFIX, bytes]),
          format: "der",
          type: "pkcs8",
        }
      : bytes.toString("utf8").trim().startsWith("-----BEGIN")
        ? { key: bytes, format: "pem", type: "pkcs8" }
        : { key: bytes, format: "der", type: "pkcs8" };
  try {
    const key = createPrivateKey(keyInput);
    if (key.asymmetricKeyType !== "ed25519") fail("private key is not Ed25519");
    return key;
  } catch {
    fail("private key material is invalid");
  }
}

/** @param {KeySource} [options] */

async function readPrivateKeySource({
  privateKeyFile,
  privateKeyFd,
  privateKeyEnv = PRIVATE_KEY_ENV,
} = {}) {
  const sources = [
    privateKeyFile !== undefined,
    privateKeyFd !== undefined,
    process.env[privateKeyEnv] !== undefined,
  ];
  if (sources.filter(Boolean).length !== 1) {
    fail("exactly one private key file, file descriptor, or environment value is required");
  }
  if (privateKeyFile !== undefined) {
    const stats = await lstat(privateKeyFile, { bigint: true }).catch(() =>
      fail("private key file is unavailable"),
    );
    if (!stats.isFile() || stats.isSymbolicLink())
      fail("private key file must be a regular non-symlink file");
    const resolvedPath = await realpath(privateKeyFile).catch(() =>
      fail("private key file is unavailable"),
    );
    const resolvedStats = await lstat(resolvedPath, { bigint: true }).catch(() =>
      fail("private key file is unavailable"),
    );
    assertStableFileMetadata(stats, resolvedStats, "private key file");
    const bytes = await readRegularFile(privateKeyFile, "private key file", resolvedStats);
    return privateKeyFromBytes(
      bytes.length === 32 ? bytes : decodePrivateKeyText(bytes.toString("utf8")),
    );
  }
  if (privateKeyFd !== undefined) {
    if (!/^\d+$/.test(String(privateKeyFd)) || Number(privateKeyFd) > 1_000_000)
      fail("private key file descriptor is invalid");
    const bytes = await readKeyDescriptor(Number(privateKeyFd)).catch(() =>
      fail("private key file descriptor is unavailable"),
    );
    return privateKeyFromBytes(
      bytes.length === 32 ? bytes : decodePrivateKeyText(bytes.toString("utf8")),
    );
  }
  const value = process.env[privateKeyEnv];
  if (value === undefined) fail("private key environment value is unavailable");
  if (value.startsWith("hex:")) return privateKeyFromBytes(Buffer.from(value.slice(4), "hex"));
  if (value.startsWith("base64url:"))
    return privateKeyFromBytes(Buffer.from(value.slice("base64url:".length), "base64url"));
  return privateKeyFromBytes(decodePrivateKeyText(value));
}

/** @param {string} filePath @param {string} label @returns {Promise<unknown>} */

async function readJsonFile(filePath, label) {
  const stats = await lstat(filePath, { bigint: true }).catch(() =>
    fail(`${label} is unavailable`),
  );
  if (stats.isSymbolicLink() || !stats.isFile())
    fail(`${label} must be a regular non-symlink file`);
  const resolvedPath = await realpath(filePath).catch(() => fail(`${label} is unavailable`));
  const resolvedStats = await lstat(resolvedPath, { bigint: true }).catch(() =>
    fail(`${label} is unavailable`),
  );
  assertStableFileMetadata(stats, resolvedStats, label);
  const bytes = await readRegularFile(filePath, label, resolvedStats, MAX_DOCUMENT_BYTES);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(`${label} is not valid UTF-8`);
  }
  try {
    return JSON.parse(text);
  } catch {
    fail(`${label} is not valid JSON`);
  }
}

/** @param {string} path */

async function canonicalPathWithMissingTail(path) {
  const missingTail = [];
  let current = resolve(path);
  while (true) {
    try {
      const canonical = await realpath(current);
      return join(canonical, ...missingTail.reverse());
    } catch (error) {
      if (!(error instanceof Error && "code" in error && error.code === "ENOENT"))
        fail("output destination cannot be resolved");
      const parent = dirname(current);
      if (parent === current) fail("output destination cannot be resolved");
      missingTail.push(basename(current));
      current = parent;
    }
  }
}

/** @param {string} candidate @param {string} repositoryRoot @param {string} inputRoot */

function assertOutputDoesNotOverlap(candidate, repositoryRoot, inputRoot) {
  if (pathsOverlap(repositoryRoot, candidate)) {
    fail("output directory must be outside the repository");
  }
  if (pathsOverlap(inputRoot, candidate)) {
    fail("output directory must not overlap the input tree");
  }
}

/** @param {string} outputDirectory */

async function assertOutputDoesNotExist(outputDirectory) {
  try {
    const existing = await lstat(outputDirectory);
    if (existing.isSymbolicLink()) fail("output directory must not be a symlink");
    fail("output directory already exists; choose a new immutable destination");
  } catch (error) {
    if (error instanceof ReleasePackagerError) throw error;
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT"))
      fail("output destination cannot be inspected");
  }
}

/** @param {string} directory */

async function createMissingDirectories(directory) {
  const missing = [];
  let current = resolve(directory);
  while (true) {
    try {
      await realpath(current);
      break;
    } catch (error) {
      if (!(error instanceof Error && "code" in error && error.code === "ENOENT"))
        fail("output parent is unavailable");
      const parent = dirname(current);
      if (parent === current) fail("output parent is unavailable");
      missing.push(current);
      current = parent;
    }
  }

  const created = [];
  try {
    for (const path of missing.reverse()) {
      try {
        await mkdir(path, { recursive: false });
        created.push(path);
      } catch (error) {
        if (!(error instanceof Error && "code" in error && error.code === "EEXIST"))
          fail("output parent is unavailable");
        await realpath(path).catch(() => fail("output parent is unavailable"));
      }
    }
  } catch (error) {
    await removeCreatedDirectories(created);
    throw error;
  }
  return created;
}

/** @param {string[]} directories */

async function removeCreatedDirectories(directories) {
  for (const directory of directories.slice().reverse()) {
    await rmdir(directory).catch(() => {});
  }
}

/** @param {string} outputDirectory @param {string} inputRoot */

async function ensureOutputDestination(outputDirectory, inputRoot) {
  const resolvedOutput = resolve(outputDirectory);
  const repositoryRoot = await realpath(REPOSITORY_ROOT).catch(() =>
    fail("repository root is unavailable"),
  );
  const canonicalBefore = await canonicalPathWithMissingTail(resolvedOutput);
  assertOutputDoesNotOverlap(canonicalBefore, repositoryRoot, inputRoot);
  await assertOutputDoesNotExist(resolvedOutput);

  /** @type {string[]} */
  let createdParentDirectories = [];
  try {
    createdParentDirectories = await createMissingDirectories(dirname(canonicalBefore));
    const canonicalAfter = await canonicalPathWithMissingTail(resolvedOutput);
    assertOutputDoesNotOverlap(canonicalAfter, repositoryRoot, inputRoot);
    await assertOutputDoesNotExist(resolvedOutput);
    return { path: canonicalAfter, createdParentDirectories };
  } catch (error) {
    await removeCreatedDirectories(createdParentDirectories);
    throw error;
  }
}

/** @param {string} filePath @param {Buffer} bytes */

async function writeAtomic(filePath, bytes) {
  const temporaryPath = `${filePath}.tmp-${process.pid}-${randomUUID()}`;
  let handle;
  try {
    handle = await open(temporaryPath, "wx", 0o644);
    await handle.writeFile(bytes);
    await handle.sync();
    await handle.close();
    handle = undefined;
    await rename(temporaryPath, filePath);
  } catch (error) {
    await handle?.close().catch(() => {});
    await rm(temporaryPath, { force: true }).catch(() => {});
    if (error instanceof ReleasePackagerError) throw error;
    fail(`could not atomically write ${filePath}`);
  }
}

/** @param {string} outputDirectory @param {Buffer} envelopeBytes @param {readonly Readonly<Artifact>[]} artifacts */

async function writePackage(outputDirectory, envelopeBytes, artifacts) {
  const parent = dirname(outputDirectory);
  const staging = join(parent, `.frontend-release-package-${process.pid}-${randomUUID()}`);
  await mkdir(staging, { recursive: false });
  try {
    await writeAtomic(join(staging, "release.json"), envelopeBytes);
    for (const artifact of artifacts) {
      const artifactPath = join(staging, "artifacts", ...artifact.path.split("/"));
      if (!isWithin(join(staging, "artifacts"), artifactPath))
        fail(`artifact ${artifact.path} escapes the output root`);
      await mkdir(dirname(artifactPath), { recursive: true });
      await writeAtomic(artifactPath, artifact.bytes);
    }
    await rename(staging, outputDirectory);
  } catch (error) {
    await rm(staging, { recursive: true, force: true }).catch(() => {});
    throw error;
  }
}

/** @param {BuildOptions} options */

export async function buildRelease({
  inputDirectory,
  metadata,
  artifactOrigin,
  keyId,
  privateKey,
  afterSnapshot,
}) {
  if (!inputDirectory) fail("input directory is required");
  const inventory = freezeArtifactSnapshot(await enumerateArtifacts(inputDirectory));
  if (afterSnapshot !== undefined) {
    if (typeof afterSnapshot !== "function") fail("afterSnapshot must be a function");
    await afterSnapshot(inventory.root);
  }
  const release = buildReleasePayload({ inventory, metadata, artifactOrigin });
  await validateReleaseOutput(inventory.root, release.metadata.remoteName, REPOSITORY_ROOT, {
    artifactSnapshot: inventory,
  });
  const signed = createSignedEnvelope({ payloadBytes: release.payloadBytes, keyId, privateKey });
  return {
    inputRoot: inventory.root,
    artifacts: inventory.artifacts,
    release: release.release,
    releaseId: release.releaseId,
    payloadBytes: release.payloadBytes,
    envelope: signed.envelope,
    documentBytes: signed.documentBytes,
    metadata: release.metadata,
  };
}

/** @param {PackageOptions} options */

export async function packageRelease({
  inputDirectory,
  outputDirectory,
  metadata,
  artifactOrigin,
  keyId,
  privateKey,
  afterSnapshot,
}) {
  if (!outputDirectory) fail("output directory is required");
  const built = await buildRelease({
    inputDirectory,
    metadata,
    artifactOrigin,
    keyId,
    privateKey,
    afterSnapshot,
  });
  const destination = await ensureOutputDestination(outputDirectory, built.inputRoot);
  try {
    await writePackage(destination.path, built.documentBytes, built.artifacts);
  } catch (error) {
    await removeCreatedDirectories(destination.createdParentDirectories);
    throw error;
  }
  return { ...built, outputDirectory: destination.path };
}

function usage() {
  return `Usage:
  node tools/frontend-release-package.mjs --input-dir DIR --metadata FILE \
    --artifact-origin https://cdn.example.com --key-id KEY_ID \
    --output-dir OUTSIDE_REPOSITORY_DIR [--private-key-file FILE | --private-key-fd FD]

The private key may also be supplied through ${PRIVATE_KEY_ENV} as PEM, 64 hex
characters, or a hex:/base64url: prefixed value. The metadata file must provide
explicit application/package/surface/query/actions, remote/module,
hostCompatibility, provenance, and releasedAt values. No timestamp or Git value
is inferred. The output directory must not already exist and contains release.json
plus an artifacts/ tree with exact input bytes.
`;
}

/** @param {string[]} argv @returns {{help:true} | ({help?:false} & CliOptions)} */

function parseArgs(argv) {
  /** @type {Record<string,string>} */
  const options = {};
  const aliases = new Map([
    ["--input", "inputDirectory"],
    ["--input-dir", "inputDirectory"],
    ["--metadata", "metadataFile"],
    ["--artifact-origin", "artifactOrigin"],
    ["--key-id", "keyId"],
    ["--output", "outputDirectory"],
    ["--output-dir", "outputDirectory"],
    ["--private-key-file", "privateKeyFile"],
    ["--private-key-fd", "privateKeyFd"],
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === undefined) fail("argument list is sparse");
    if (argument === "--help" || argument === "-h") return { help: true };
    if (argument === "--") {
      if (index !== 0) fail("unexpected option separator");
      continue;
    }
    const name = argument.includes("=") ? argument.slice(0, argument.indexOf("=")) : argument;
    const key = aliases.get(name);
    if (!key) fail(`unknown option ${argument}`);
    const value = argument.includes("=")
      ? argument.slice(argument.indexOf("=") + 1)
      : argv[++index];
    if (!value || value.startsWith("--")) fail(`${name} requires a value`);
    if (options[key] !== undefined) fail(`${name} was provided more than once`);
    options[key] = value;
  }
  for (const key of [
    "inputDirectory",
    "metadataFile",
    "artifactOrigin",
    "keyId",
    "outputDirectory",
  ]) {
    if (options[key] === undefined)
      fail(`--${key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)} is required`);
  }
  const requiredOption = (/** @type {string} */ key) => options[key] ?? fail(`missing ${key}`);
  return {
    inputDirectory: requiredOption("inputDirectory"),
    metadataFile: requiredOption("metadataFile"),
    artifactOrigin: requiredOption("artifactOrigin"),
    keyId: requiredOption("keyId"),
    outputDirectory: requiredOption("outputDirectory"),
    ...(options.privateKeyFile === undefined ? {} : { privateKeyFile: options.privateKeyFile }),
    ...(options.privateKeyFd === undefined ? {} : { privateKeyFd: options.privateKeyFd }),
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }
  const metadata = await readJsonFile(options.metadataFile, "metadata file");
  const privateKey = await readPrivateKeySource(options);
  const result = await packageRelease({ ...options, metadata, privateKey });
  process.stdout.write(
    `${JSON.stringify({
      outputDirectory: result.outputDirectory,
      releaseId: result.releaseId,
      artifactCount: result.artifacts.length,
      envelope: join(result.outputDirectory, "release.json"),
    })}\n`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main().catch((error) => {
    const message =
      error instanceof ReleasePackagerError
        ? error.message
        : "unexpected release packaging failure";
    process.stderr.write(`release packager: ${message}\n`);
    process.exitCode = 1;
  });
}

export {
  ALGORITHM,
  ENVELOPE_SCHEMA,
  HOST_CONTRACT,
  PAYLOAD_ENCODING,
  RELEASE_SCHEMA,
  canonicalJson,
  createSignedEnvelope,
  buildReleasePayload,
  enumerateArtifacts,
  mediaTypeForPath,
  readPrivateKeySource,
  sha256Digest,
  validateMetadata,
  validateRelativeArtifactPath,
};

// The callback API accepts a caller-owned descriptor; fs/promises.readFile accepts FileHandle instead.
/** @param {number} descriptor @returns {Promise<Buffer>} */
function readKeyDescriptor(descriptor) {
  return new Promise((resolveKey, rejectKey) => {
    readDescriptor(descriptor, (error, bytes) => (error ? rejectKey(error) : resolveKey(bytes)));
  });
}
