#!/usr/bin/env node

import {
  constants as fsConstants,
  createHash,
  createPrivateKey,
  randomUUID,
  sign,
} from "node:crypto";
import { mkdir, open, readFile, readdir, realpath, rename, rm, lstat } from "node:fs/promises";
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

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
  constructor(message) {
    super(message);
    this.name = "ReleasePackagerError";
  }
}

function fail(message) {
  throw new ReleasePackagerError(message);
}

function compareUtf8(left, right) {
  return Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"));
}

function isPlainRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactFields(value, required, label) {
  if (!isPlainRecord(value)) fail(`${label} must be an object`);
  const actual = Object.keys(value);
  const allowed = new Set(required);
  if (actual.length !== required.length || actual.some((key) => !allowed.has(key))) {
    fail(`${label} has an unexpected or missing field`);
  }
}

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

function requireIdentifier(value, label) {
  requireString(value, label, { maxBytes: MAX_IDENTIFIER_BYTES, nonEmpty: true });
  if (!/^[a-z][a-z0-9._-]{0,127}$/.test(value)) fail(`${label} is not a safe identifier`);
  return value;
}

function requireVersion(value, label) {
  if (!Number.isSafeInteger(value) || value < 1 || value > MAX_VERSION) {
    fail(`${label} is not a valid version`);
  }
  return value;
}

function requireIdentity(value, label) {
  exactFields(value, ["id", "version"], label);
  return {
    id: requireIdentifier(value.id, `${label}.id`),
    version: requireVersion(value.version, `${label}.version`),
  };
}

function requireTimestamp(value, label) {
  requireString(value, label);
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

function strictHttpsUrl(value, label, { originOnly = false } = {}) {
  requireString(value, label);
  if (
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

function validateRelativeArtifactPath(value, label = "artifact path") {
  requireString(value, label, { maxBytes: MAX_ARTIFACT_PATH_BYTES, nonEmpty: true });
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

function isWithin(root, candidate) {
  const remainder = relative(root, candidate);
  return (
    remainder === "" ||
    (!remainder.startsWith(`..${sep}`) && remainder !== ".." && !isAbsolute(remainder))
  );
}

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

async function readRegularFile(filePath, label) {
  const noFollow = fsConstants.O_NOFOLLOW ?? 0;
  let handle;
  try {
    handle = await open(filePath, fsConstants.O_RDONLY | noFollow);
    const stats = await handle.stat();
    if (!stats.isFile()) fail(`${label} is not a regular file`);
    if (stats.size > MAX_ARTIFACT_SIZE) fail(`${label} is too large`);
    const bytes = await handle.readFile();
    if (bytes.byteLength !== stats.size) fail(`${label} changed while it was read`);
    return bytes;
  } catch (error) {
    if (error instanceof ReleasePackagerError) throw error;
    fail(`${label} could not be read`);
  } finally {
    await handle?.close().catch(() => {});
  }
}

async function enumerateArtifacts(inputDirectory) {
  const inputStats = await lstat(inputDirectory).catch(() =>
    fail("input directory does not exist"),
  );
  if (inputStats.isSymbolicLink()) fail("input directory must not be a symlink");
  if (!inputStats.isDirectory()) fail("input path must be a directory");
  const root = await realpath(inputDirectory).catch(() => fail("input directory does not exist"));
  const rootStats = await lstat(root);
  if (!rootStats.isDirectory()) fail("input path must be a directory");

  const artifacts = [];
  const paths = new Set();

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

      const stats = await lstat(absolutePath).catch(() =>
        fail(`artifact ${relativePath} disappeared`),
      );
      if (stats.isDirectory()) {
        await visit(absolutePath);
        continue;
      }
      if (!stats.isFile()) fail(`artifact ${relativePath} is not a regular file`);

      const resolvedPath = await realpath(absolutePath).catch(() =>
        fail(`artifact ${relativePath} is unreadable`),
      );
      if (!isWithin(root, resolvedPath)) fail(`artifact ${relativePath} escapes the input root`);
      const bytes = await readRegularFile(absolutePath, `artifact ${relativePath}`);
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
  strictHttpsUrl(metadata.provenance.sourceRepository, "provenance.sourceRepository");
  requireString(metadata.provenance.sourceRevision, "provenance.sourceRevision", {
    nonEmpty: true,
  });
  if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(metadata.provenance.sourceRevision)) {
    fail("provenance.sourceRevision must be a lowercase Git revision");
  }
  for (const key of ["buildId", "builder", "workflow"]) {
    requireString(metadata.provenance[key], `provenance.${key}`);
  }
  requireTimestamp(metadata.provenance.builtAt, "provenance.builtAt");
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
      sourceRepository: metadata.provenance.sourceRepository,
      sourceRevision: metadata.provenance.sourceRevision,
      buildId: metadata.provenance.buildId,
      builder: metadata.provenance.builder,
      workflow: metadata.provenance.workflow,
      builtAt: metadata.provenance.builtAt,
    },
    releasedAt,
  };
}

function buildReleasePayload({ inventory, metadata, artifactOrigin }) {
  if (!inventory || !Array.isArray(inventory.artifacts)) fail("artifact inventory is required");
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
      !Number.isSafeInteger(artifact.size) ||
      artifact.size < 0 ||
      artifact.size > MAX_ARTIFACT_SIZE
    ) {
      fail(`invalid size for ${path}`);
    }
    if (mediaTypeForPath(path) !== artifact.mediaType) {
      fail(`invalid media type for ${path}`);
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

function sha256Digest(bytes) {
  return `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
}

function base64Url(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

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

function decodePrivateKeyText(text) {
  const trimmed = text.trim();
  if (trimmed.startsWith("-----BEGIN")) return Buffer.from(text, "utf8");
  if (/^[0-9a-fA-F]{64}$/.test(trimmed)) return Buffer.from(trimmed, "hex");
  if (/^[A-Za-z0-9_-]{43}$/.test(trimmed)) return Buffer.from(trimmed, "base64url");
  fail("private key material has an unsupported encoding");
}

function privateKeyFromBytes(bytes) {
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
    const stats = await lstat(privateKeyFile).catch(() => fail("private key file is unavailable"));
    if (!stats.isFile() || stats.isSymbolicLink())
      fail("private key file must be a regular non-symlink file");
    const bytes = await readRegularFile(privateKeyFile, "private key file");
    return privateKeyFromBytes(
      bytes.length === 32 ? bytes : decodePrivateKeyText(bytes.toString("utf8")),
    );
  }
  if (privateKeyFd !== undefined) {
    if (!/^\d+$/.test(String(privateKeyFd)) || Number(privateKeyFd) > 1_000_000)
      fail("private key file descriptor is invalid");
    const bytes = await readFile(`/dev/fd/${Number(privateKeyFd)}`).catch(() =>
      fail("private key file descriptor is unavailable"),
    );
    return privateKeyFromBytes(
      bytes.length === 32 ? bytes : decodePrivateKeyText(bytes.toString("utf8")),
    );
  }
  const value = process.env[privateKeyEnv];
  if (value.startsWith("hex:")) return privateKeyFromBytes(Buffer.from(value.slice(4), "hex"));
  if (value.startsWith("base64url:"))
    return privateKeyFromBytes(Buffer.from(value.slice("base64url:".length), "base64url"));
  return privateKeyFromBytes(decodePrivateKeyText(value));
}

async function readJsonFile(filePath, label) {
  const bytes = await readFile(filePath).catch(() => fail(`${label} is unavailable`));
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

async function ensureOutputDestination(outputDirectory, inputRoot) {
  const resolvedOutput = resolve(outputDirectory);
  if (isWithin(REPOSITORY_ROOT, resolvedOutput)) {
    fail("output directory must be outside the repository");
  }
  if (isWithin(inputRoot, resolvedOutput) || isWithin(resolvedOutput, inputRoot)) {
    fail("output directory must not overlap the input tree");
  }
  const parent = dirname(resolvedOutput);
  await mkdir(parent, { recursive: true });
  const parentReal = await realpath(parent).catch(() => fail("output parent is unavailable"));
  if (isWithin(REPOSITORY_ROOT, parentReal))
    fail("output directory must be outside the repository");
  try {
    const existing = await lstat(resolvedOutput);
    if (existing.isSymbolicLink()) fail("output directory must not be a symlink");
    fail("output directory already exists; choose a new immutable destination");
  } catch (error) {
    if (error instanceof ReleasePackagerError) throw error;
    if (error?.code !== "ENOENT") fail("output destination cannot be inspected");
  }
  return resolvedOutput;
}

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

export async function buildRelease({
  inputDirectory,
  metadata,
  artifactOrigin,
  keyId,
  privateKey,
}) {
  if (!inputDirectory) fail("input directory is required");
  const inventory = await enumerateArtifacts(inputDirectory);
  const release = buildReleasePayload({ inventory, metadata, artifactOrigin });
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

export async function packageRelease({
  inputDirectory,
  outputDirectory,
  metadata,
  artifactOrigin,
  keyId,
  privateKey,
}) {
  if (!outputDirectory) fail("output directory is required");
  const built = await buildRelease({ inputDirectory, metadata, artifactOrigin, keyId, privateKey });
  const output = await ensureOutputDestination(outputDirectory, built.inputRoot);
  await writePackage(output, built.documentBytes, built.artifacts);
  return { ...built, outputDirectory: output };
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

function parseArgs(argv) {
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
    if (argument === "--help" || argument === "-h") return { help: true };
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
  return options;
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
