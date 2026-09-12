import type { DeclarationPage, DeclarationAction, DeclarationOperation } from "./declaration";
export const declarationFixture = (): DeclarationPage => ({
  model: {
    contract_version: 1,
    context: { organization_id: "org-1", mission_id: "mission-1", actor_id: "user-1" },
    horizon: { earliest_start: "2027-01-01T01:00:37Z", latest_end: "2027-01-02T01:00:37Z" },
    spacecraft: { page: 1, total: 1, entries: [{ id: "craft-1", name: "Test spacecraft" }] },
    can_declare: true,
  },
  sequence: 0,
  operation: null,
});
export function declarationOperation(
  page: DeclarationPage,
  action: DeclarationAction,
  command: any,
): DeclarationOperation {
  const result =
    action === "validate"
      ? { valid: true, feedback: [] }
      : action === "spacecraft-page"
        ? {
            spacecraft: {
              page: command.payload.page,
              total: 26,
              entries: [{ id: "craft-26", name: "Last spacecraft" }],
            },
          }
        : {
            contract_version: 1,
            ...page.model.context,
            requirement_id: "created-need",
            requirement_version: 1,
            content_sha256: "a".repeat(64),
          };
  return {
    sequence: command.sequence,
    action,
    input: structuredClone(command.payload),
    status: "completed",
    receipt: {
      receiptId: `receipt-${command.sequence}`,
      completedAt: "2027-01-01T00:00:00Z",
      result,
    },
  };
}
