import type { Argument, AuthoringPage, Preview } from "./contracts";
const argument = (
  name: string,
  type: Argument["type"],
  required: boolean,
  default_value: string | number | boolean | null = null,
  fixed_value: string | number | boolean | null = null,
): Argument => ({
  id: `argument_${name}`,
  name,
  type,
  required,
  description: null,
  default_value_json: default_value === null ? null : JSON.stringify(default_value),
  fixed_value_json: fixed_value === null ? null : JSON.stringify(fixed_value),
  hazardous_values_json: "[]",
});
export function pageFixture(): AuthoringPage {
  const target = {
    id: "target_one",
    name: "Flight command endpoint",
    spacecraft_id: "craft_one",
    source_ref: "flight:uplink",
    scid: 7,
  };
  const command = { id: "command_one", name: "SET_POWER", display_name: "Set power" };
  return {
    catalog: {
      version: 2,
      context: { organizationId: "org_one", missionId: "mission_one" },
      actor_id: "user_one",
      mission_name: "Flight mission",
      observed_at: "2026-09-10T10:00:00.123456Z",
      query: {
        command: command.id,
        target: target.id,
        command_after: "",
        target_after: "",
        command_query: "",
        target_query: "",
      },
      basis: {
        token: "a".repeat(64),
        activation_id: "activation_one",
        generation: 1,
        revision_id: "model_one",
        plan_id: "plan_one",
      },
      targets: { limit: 25, entries: [target], next_after: null },
      commands: { limit: 25, entries: [command], next_after: null },
      selected_target: target,
      selected_command: {
        ...command,
        description: "Adjust spacecraft power",
        critical: true,
        hazardous: true,
        significance: "hazardous",
        supported: true,
        arguments: [
          argument("amount", "integer", true),
          argument("delay_s", "integer", false, 5),
          argument("enabled", "boolean", false),
          argument("channel", "string", true, null, "primary"),
        ],
      },
    },
    preview: null,
    operation: null,
  };
}
export function previewFixture(): Preview {
  const c = pageFixture().catalog;
  return {
    token: "b".repeat(64),
    request_id: "request_one",
    target: c.selected_target!,
    revision_id: c.basis.revision_id,
    command_id: c.selected_command!.id,
    command_name: "SET_POWER",
    command_display_name: "Set power",
    actor_id: c.actor_id,
    priority: 3,
    not_before: null,
    expires_at: null,
    requested_at: "2026-09-10T10:01:00.123456Z",
    lifecycle_state: "approval_pending",
    argument_values_json: JSON.stringify({ amount: 2, enabled: false }),
    resolved_argument_values_json: JSON.stringify({
      amount: 2,
      delay_s: 5,
      enabled: false,
      channel: "primary",
    }),
    critical: true,
    hazardous: true,
    significance: "hazardous",
  };
}
