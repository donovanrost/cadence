import { admitDeclarationOperation, isDeclarationCommand } from "./declaration";
import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import { record } from "@cadence/plugin-sdk/admission";
import type { DeclarationPage, DeclarationAction, DeclarationOperation } from "./declaration";
export const declarationFixture = (): MutableFixture<DeclarationPage> => ({
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
type Completed<A extends DeclarationAction = DeclarationAction> = MutableFixture<
  Extract<DeclarationOperation, { action: A; status: "completed" }>
>;
export function declarationOperation<A extends DeclarationAction>(
  page: DeclarationPage,
  action: A,
  command: unknown,
): Completed<A>;
export function declarationOperation(
  page: DeclarationPage,
  action: DeclarationAction,
  command: unknown,
): Completed {
  if (!record(command) || typeof command.sequence !== "number")
    throw Error("Invalid command fixture");
  const request = { action, input: command.payload };
  if (!isDeclarationCommand(request)) throw Error("Invalid declaration input fixture");
  const result =
    request.action === "validate"
      ? { valid: true, feedback: [] }
      : request.action === "spacecraft-page"
        ? {
            spacecraft: {
              page: request.input.page,
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
  const operation = admitDeclarationOperation(
    {
      sequence: command.sequence,
      action: request.action,
      input: request.input,
      status: "completed",
      receipt: {
        receiptId: `receipt-${command.sequence}`,
        completedAt: "2027-01-01T00:00:00Z",
        result,
      },
    },
    page.model.context,
  );
  if (!operation || operation.status !== "completed" || operation.action !== action)
    throw Error("Invalid declaration operation fixture");
  return mutableFixture(operation);
}
