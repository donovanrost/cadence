import type { TemplatePage, TemplateAction, TemplateOperation, TemplateEntry } from "./templates";
export function templateFixture(): TemplatePage {
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
export function templateEntry(page = templateFixture(), id = "template-1"): TemplateEntry {
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
export function templateOperation(
  page: TemplatePage,
  action: TemplateAction,
  command: any,
): TemplateOperation {
  const result =
    action === "validate-template"
      ? { valid: true, feedback: [] }
      : action.endsWith("-page")
        ? { page: command.payload.page }
        : {
            contract_version: 1,
            actor_id: page.model.context.actor_id,
            reference:
              action === "create-template"
                ? templateEntry(page, "template-created").reference
                : {
                    ...command.payload.reference,
                    lifecycle_state:
                      action === "pause-template"
                        ? "paused"
                        : action === "activate-template"
                          ? "active"
                          : "closed",
                    lifecycle_changed_at: "2027-01-01T02:00:00Z",
                    lifecycle_changed_by: page.model.context.actor_id,
                  },
          };
  return {
    sequence: command.sequence,
    action,
    input: structuredClone(command.payload),
    status: "completed",
    receipt: {
      receiptId: `receipt-${command.sequence}`,
      completedAt: "2027-01-01T02:00:00Z",
      result,
    },
  };
}
