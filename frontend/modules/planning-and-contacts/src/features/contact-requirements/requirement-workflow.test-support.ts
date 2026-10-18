import {
  admitRequirementOperation,
  isRequirementCommand,
  requirementContext,
} from "./requirement-workflow";
import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import { record } from "@cadence/plugin-sdk/admission";
import { requirementDetailFixture } from "./requirement-detail.test-support";
import type { RequirementDirectory } from "./requirement-directory";
import type {
  RequirementPage,
  RequirementAction,
  RequirementOperation,
} from "./requirement-workflow";
import { requirementSegment } from "./requirement-directory";
export const requirementPageFixture = (): MutableFixture<RequirementPage> => ({
  detail: requirementDetailFixture(),
  sequence: 0,
  operation: null,
});
export function requirementDirectoryFixture(): RequirementDirectory {
  const d = requirementDetailFixture(),
    r = d.requirement;
  return {
    contract_version: 1,
    context: { organization_id: d.context.organization_id, mission_id: d.context.mission_id },
    query: { page: 1, state: "all" },
    requirements: {
      page: 1,
      more: false,
      entries: [
        {
          id: r.id,
          version: r.version,
          state: r.lifecycle_state,
          priority: r.priority as "high",
          direction: r.direction,
          intent: r.intent,
          earliest_start: r.earliest_start,
          latest_end: r.latest_end,
          success_measure: "minimum_duration",
          minimum_duration_seconds: 60,
          minimum_data_volume_bytes: null,
          contact_count: null,
          minimum_separation_seconds: 0,
        },
      ],
    },
  };
}
type Completed<A extends RequirementAction = RequirementAction> = MutableFixture<
  Extract<RequirementOperation, { action: A; status: "completed" }>
>;
export function requirementOperationFixture<A extends RequirementAction>(
  page: RequirementPage,
  action: A,
  command: unknown,
): Completed<A>;
export function requirementOperationFixture(
  page: RequirementPage,
  action: RequirementAction,
  command: unknown,
): Completed {
  if (!record(command) || typeof command.sequence !== "number")
    throw Error("Invalid command fixture");
  const request = { action, input: command.payload };
  if (!isRequirementCommand(request, requirementContext(page.detail)))
    throw Error("Invalid requirement input fixture");
  const d = page.detail,
    base = `/missions/${requirementSegment(d.context.mission_id)}/ops/`;
  const result =
    request.action === "plan"
      ? {
          contactRequirementId: d.requirement.id,
          planningRunId: "run-new",
          searchCount: 1,
          opportunityCount: 1,
          navigation: {
            href:
              base +
              `requirements/${requirementSegment(d.requirement.id)}?planning_run_id=run-new&version=${d.requirement.version}`,
          },
        }
      : {
          contactPlanId: "plan-new",
          version: 1,
          contentSha256: "f".repeat(64),
          actorId: d.context.actor_id,
          requirementEvidence: request.input.requirement_evidence,
          planningRunId: request.input.planning_run_id,
          navigation: { href: base + "plans/plan-new" },
        };
  const operation = admitRequirementOperation(
    {
      sequence: command.sequence,
      action: request.action,
      input: request.input,
      status: "completed",
      receipt: {
        receiptId: `receipt-${command.sequence}`,
        completedAt: "2026-09-09T00:00:00Z",
        result,
      },
    },
    requirementContext(page.detail),
  );
  if (!operation || operation.status !== "completed" || operation.action !== action)
    throw Error("Invalid requirement operation fixture");
  return mutableFixture(operation);
}
