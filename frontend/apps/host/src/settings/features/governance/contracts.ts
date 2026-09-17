export type ApprovalValue = Readonly<{ approval_requirement: "direct" | "independent" }>;
export const approvalNames = {
  direct: "One authorized operator",
  independent: "Independent approval",
} as const;
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
export function readApprovalValue(value: unknown): ApprovalValue {
  if (
    !record(value) ||
    (value.approval_requirement !== "direct" && value.approval_requirement !== "independent")
  )
    throw new Error("Invalid approval requirement.");
  return { approval_requirement: value.approval_requirement };
}
export function readMissionImpact(value: unknown) {
  if (
    !record(value) ||
    !Array.isArray(value.missions) ||
    value.missions.length > 100 ||
    typeof value.missions_total !== "number" ||
    !Number.isSafeInteger(value.missions_total) ||
    value.missions_total < value.missions.length
  )
    throw new Error("Invalid mission impact summary.");
  const entries: unknown[] = value.missions;
  const items = entries.map((entry) => {
    if (
      !record(entry) ||
      typeof entry.id !== "string" ||
      !entry.id ||
      typeof entry.name !== "string"
    )
      throw new Error("Invalid mission impact.");
    return {
      id: entry.id,
      name: entry.name,
      override: entry.override === null ? null : readApprovalValue(entry.override),
    };
  });
  return { total: value.missions_total, items };
}
