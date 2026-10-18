import { admitTemplateOperation, isTemplateCommand } from "./templates";
import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import { record } from "@cadence/plugin-sdk/admission";
import type { TemplatePage, TemplateAction, TemplateOperation, TemplateEntry } from "./templates";
export function templateFixture(): MutableFixture<TemplatePage> {
  return {
    model: {
      contract_version: 1,
      context: { organization_id: "org-1", mission_id: "mission-1", actor_id: "user-1" },
      defaults: { anchor_at: "2027-01-01T01:00:37Z", time_utc: "01:00:37" },
      can_manage: true,
      templates: { page: 1, more: false, entries: [] },
      spacecraft: { page: 1, total: 1, entries: [{ id: "craft-1", name: "Spacecraft one" }] },
    },
    sequence: 0,
    operation: null,
  };
}
export function templateEntry(
  page: TemplatePage = templateFixture(),
  id = "template-1",
): MutableFixture<TemplateEntry> {
  return {
    reference: {
      organization_id: page.model.context.organization_id,
      mission_id: page.model.context.mission_id,
      template_id: id,
      version: 1,
      content_sha256: "a".repeat(64),
      lifecycle_state: "active",
      lifecycle_changed_at: "2027-01-01T01:00:00Z",
      lifecycle_changed_by: page.model.context.actor_id,
    },
    spacecraft_id: "craft-1",
    contact_intent: "payload_downlink",
    schedule: {
      type: "fixed_interval",
      anchor_at: "2027-01-01T01:00:37Z",
      ends_at: null,
      window_offset_seconds: 0,
      window_duration_seconds: 1800,
      interval_seconds: 21600,
    },
  };
}
type Completed<A extends TemplateAction = TemplateAction> = MutableFixture<
  Extract<TemplateOperation, { action: A; status: "completed" }>
>;
export function templateOperation<A extends TemplateAction>(
  page: TemplatePage,
  action: A,
  command: unknown,
): Completed<A>;
export function templateOperation(
  page: TemplatePage,
  action: TemplateAction,
  command: unknown,
): Completed {
  if (!record(command) || typeof command.sequence !== "number")
    throw Error("Invalid command fixture");
  const request = { action, input: command.payload };
  if (!isTemplateCommand(request, page.model.context))
    throw Error("Invalid template input fixture");
  const result =
    request.action === "validate-template"
      ? { valid: true, feedback: [] }
      : request.action === "spacecraft-page" || request.action === "templates-page"
        ? { page: request.input.page }
        : {
            contract_version: 1,
            actor_id: page.model.context.actor_id,
            reference:
              request.action === "create-template"
                ? templateEntry(page, "template-created").reference
                : {
                    ...request.input.reference,
                    lifecycle_state:
                      request.action === "pause-template"
                        ? "paused"
                        : request.action === "activate-template"
                          ? "active"
                          : "closed",
                    lifecycle_changed_at: "2027-01-01T02:00:00Z",
                    lifecycle_changed_by: page.model.context.actor_id,
                  },
          };
  const operation = admitTemplateOperation(
    {
      sequence: command.sequence,
      action: request.action,
      input: request.input,
      status: "completed",
      receipt: {
        receiptId: `receipt-${command.sequence}`,
        completedAt: "2027-01-01T02:00:00Z",
        result,
      },
    },
    page.model.context,
  );
  if (!operation || operation.status !== "completed" || operation.action !== action)
    throw Error("Invalid template operation fixture");
  return mutableFixture(operation);
}
