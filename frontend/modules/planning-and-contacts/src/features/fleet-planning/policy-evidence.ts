export type PolicyEvidence = Readonly<{
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  policy_id: string;
  policy_version: number;
  content_sha256: string;
}>;

const keys = [
  "contract_version",
  "organization_id",
  "mission_id",
  "policy_id",
  "policy_version",
  "content_sha256",
] as const;
const identifier = (value: unknown): value is string =>
  typeof value === "string" &&
  new TextEncoder().encode(value).length >= 1 &&
  new TextEncoder().encode(value).length <= 256 &&
  !/[\x00-\x20\x7f]/.test(value);

// Fail closed for stale renderer/server contracts; a missing reference must never
// fall back to whichever policy is current when the user clicks.
export function admitPolicyEvidence(value: unknown): PolicyEvidence | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (
    Object.keys(record).length !== keys.length ||
    !keys.every((key) => Object.hasOwn(record, key))
  )
    return null;
  if (
    record.contract_version !== 1 ||
    !identifier(record.organization_id) ||
    !identifier(record.mission_id) ||
    !identifier(record.policy_id) ||
    !Number.isSafeInteger(record.policy_version) ||
    (record.policy_version as number) <= 0 ||
    typeof record.content_sha256 !== "string" ||
    record.content_sha256.length !== 64 ||
    !/^[0-9a-f]{64}$/.test(record.content_sha256)
  )
    return null;
  return Object.freeze({
    contract_version: 1,
    organization_id: record.organization_id,
    mission_id: record.mission_id,
    policy_id: record.policy_id,
    policy_version: record.policy_version as number,
    content_sha256: record.content_sha256,
  });
}

export const policyEvidenceKey = (value: PolicyEvidence | null): string =>
  value ? JSON.stringify(value) : "";

export type PolicyEditReference = Readonly<{
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  base: PolicyEvidence | null;
}>;

export function admitPolicyEditReference(value: unknown): PolicyEditReference | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const fields = ["contract_version", "organization_id", "mission_id", "base"];
  if (
    Object.keys(record).length !== fields.length ||
    !fields.every((key) => Object.hasOwn(record, key)) ||
    record.contract_version !== 1 ||
    !identifier(record.organization_id) ||
    !identifier(record.mission_id)
  )
    return null;
  const base = admitPolicyEvidence(record.base);
  if (
    record.base !== null &&
    (!base ||
      base.organization_id !== record.organization_id ||
      base.mission_id !== record.mission_id)
  )
    return null;
  return Object.freeze({
    contract_version: 1,
    organization_id: record.organization_id,
    mission_id: record.mission_id,
    base,
  });
}

export const policyEditReferenceKey = (value: PolicyEditReference | null): string =>
  value ? JSON.stringify(value) : "";
