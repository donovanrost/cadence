<script setup lang="ts">
import { CommandWorkspace, type WorkspacePreparation } from "@cadence/commanding/workspace";
import OpsWorkspaceFrame from "../../host/src/ops-workspace/features/frame/OpsWorkspaceFrame.vue";
import HostPage from "../../host/src/shell/HostPage.vue";
import { context } from "../../host/src/auth-and-navigation/shared/context.test-support";
import { workspaceFixture } from "../../../modules/commanding/src/features/workspace/fixtures.test-support";
import { readTargetsPreview } from "../../../modules/commanding/src/features/workspace/contracts";
import { readQueuePreview } from "../../../modules/commanding/src/features/workspace/queue-contracts";
import {
  readQuery,
  record,
  type SelectedCommand,
  type Query,
} from "../../../modules/commanding/src/shared/command-draft/contracts";
const props = withDefaults(
  defineProps<{
    initial?: "browse" | "prepared" | "staged" | "model-unavailable";
    largeCatalog?: boolean;
    withoutStage?: boolean;
  }>(),
  { initial: "browse" },
);
const fixture = workspaceFixture();
const frameContext = {
  ...context,
  mission: {
    mission_id: fixture.directory.context.missionId,
    display_name: "Kestrel",
    slug: "kestrel",
  },
};
if (!fixture.catalog || !fixture.catalog.selected_command || !fixture.workbench)
  throw Error("Invalid workspace fixture");
const base = fixture.catalog;
const sampleCommand = fixture.catalog.selected_command;
const definitions: SelectedCommand[] = [
  {
    ...sampleCommand,
    id: "command_noop",
    name: "NOOP",
    opcode_json: "0",
    display_name: "Link confidence check",
    description: "Send a no-operation command through the spacecraft command path.",
    critical: false,
    hazardous: false,
    significance: null,
    arguments: [],
  },
  {
    ...sampleCommand,
    id: "command_telemetry",
    name: "SET_TLM_RATE",
    opcode_json: "16",
    display_name: "Set telemetry rate",
    description: "Set the packet interval for the housekeeping telemetry stream.",
    critical: false,
    hazardous: false,
    significance: null,
    arguments: [
      {
        id: "argument_interval",
        name: "interval_seconds",
        description: "Housekeeping packet interval in seconds.",
        type: "integer",
        required: false,
        default_value_json: "5",
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: [],
      },
    ],
  },
  {
    ...sampleCommand,
    id: "command_attitude",
    name: "SET_ATTITUDE",
    opcode_json: "48",
    display_name: "Set attitude mode",
    description: "Select the spacecraft pointing mode.",
    critical: true,
    hazardous: false,
    significance: "critical",
    arguments: [
      {
        id: "argument_mode",
        name: "mode",
        description: "Requested pointing mode.",
        type: "enumerated",
        required: false,
        default_value_json: "0",
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: [
          "Sun pointing",
          "Nadir pointing",
          "Inertial hold",
          "Ground tracking",
          "Rate damping",
        ].map((label, value) => ({ label, value_json: String(value) })),
      },
    ],
  },
  {
    ...sampleCommand,
    id: "command_capture",
    name: "CAPTURE_IMAGE",
    opcode_json: "64",
    display_name: "Capture an image",
    description: "Prepare a payload imaging operation.",
    critical: false,
    hazardous: false,
    significance: null,
    arguments: [
      {
        id: "argument_exposure",
        name: "exposure_ms",
        description: "Camera exposure in milliseconds.",
        type: "integer",
        required: false,
        default_value_json: "25",
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: [],
      },
    ],
  },
  {
    ...sampleCommand,
    id: "command_reset",
    name: "RESET_COMPUTER",
    opcode_json: "1",
    display_name: "Reset flight computer",
    description: "Reset the onboard computer. A separate reviewer must approve the formal request.",
    critical: true,
    hazardous: true,
    significance: "hazardous",
    arguments: [],
  },
  {
    ...sampleCommand,
    id: "command_disable_load",
    name: "DISABLE_LOAD",
    display_name: null,
    description: "Disable a power load",
    opcode_json: "34",
    critical: false,
    hazardous: false,
    significance: null,
    arguments: [
      {
        id: "argument_load_id",
        name: "load_id",
        description: "Load identifier (0-15)",
        type: "integer",
        required: true,
        default_value_json: null,
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: [],
      },
    ],
  },
];
definitions.push(
  {
    ...sampleCommand,
    id: "command_heater",
    name: "SET_HEATER_SETPOINT",
    display_name: "Set heater setpoint",
    opcode_json: "18",
    description: "Set the temperature target for a spacecraft heater.",
    critical: false,
    hazardous: false,
    significance: null,
    arguments: [
      {
        id: "argument_heater_id",
        name: "heater_id",
        description: "Heater identifier.",
        type: "enumerated",
        required: true,
        default_value_json: null,
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: [
          { label: "1", value_json: "1" },
          { label: "2", value_json: "2" },
        ],
      },
      {
        id: "argument_setpoint",
        name: "setpoint",
        description: "Target temperature in °C.",
        type: "float",
        required: true,
        default_value_json: null,
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: [],
      },
    ],
  },
  {
    ...sampleCommand,
    id: "command_channel",
    name: "SELECT_CHANNEL",
    display_name: "Select downlink channel",
    opcode_json: "19",
    description: "Choose one of the seven configured downlink channels.",
    critical: false,
    hazardous: false,
    significance: null,
    arguments: [
      {
        id: "argument_channel",
        name: "channel",
        description: null,
        type: "enumerated",
        required: true,
        default_value_json: null,
        fixed_value_json: null,
        hazardous_values_json: "[]",
        choices: Array.from({ length: 7 }, (_, i) => ({
          label: `Channel ${i + 1}`,
          value_json: String(i + 1),
        })),
      },
    ],
  },
);
if (props.largeCatalog) {
  definitions.push(
    ...Array.from({ length: 60 }, (_, index) => ({
      ...sampleCommand,
      id: `command_test_${String(index + 1).padStart(3, "0")}`,
      name: `TEST_${String(index + 1).padStart(3, "0")}`,
      display_name: `Test command ${index + 1}`,
    })),
  );
}
const sorted = [...definitions].sort((a, b) => a.id.localeCompare(b.id));
const targets = Array.from({ length: props.largeCatalog ? 64 : 8 }, (_, index) => ({
  id: `endpoint_${String(index + 1).padStart(3, "0")}`,
  name: `KESTREL-${String(index + 1).padStart(2, "0")} OBC`,
  spacecraft_id: `craft_${index + 1}`,
  source_ref: `obc:${index + 1}`,
  scid: index + 1,
}));
const spacecraft = targets.map((target, index) => ({
  id: target.spacecraft_id,
  name: `KESTREL-${String(index + 1).padStart(2, "0")}`,
}));
const selected = definitions.find((item) => item.id === "command_telemetry");
if (!selected) throw Error("Missing sample command");
let current: WorkspacePreparation = {
  ...fixture,
  directory: { ...fixture.directory, mission_name: "Kestrel" },
  catalog:
    props.initial === "model-unavailable"
      ? null
      : {
          ...base,
          mission_name: "Kestrel",
          query: {
            ...base.query,
            command: props.initial === "browse" ? "" : selected.id,
            target: "",
          },
          selected_command: props.initial === "browse" ? null : selected,
          selected_target: null,
          commands: {
            limit: 25,
            entries: sorted
              .slice(0, 25)
              .map(({ id, name, display_name }) => ({ id, name, display_name })),
            next_after: sorted.length > 25 ? (sorted[24]?.id ?? null) : null,
          },
          targets: {
            limit: 25,
            entries: targets.slice(0, 25),
            next_after: targets.length > 25 ? (targets[24]?.id ?? null) : null,
          },
        },
  spacecraft: props.initial === "model-unavailable" ? [] : spacecraft.slice(0, 25),
  workbench: props.withoutStage
    ? null
    : {
        ...fixture.workbench,
        items: {
          limit: 25,
          entries:
            props.initial === "staged"
              ? targets.slice(0, 3).map((target, index) => ({
                  id: `item_${index}`,
                  expected_item: String(index + 1).repeat(64),
                  command_id: selected.id,
                  revision_id: base.basis.revision_id,
                  target_id: target.id,
                  order: index,
                  state: "draft",
                  priority: 3,
                  not_before: null,
                  expires_at: null,
                  request_id: null,
                  notes: null,
                  available: true,
                  argument_values_json: null,
                }))
              : [],
          next_after: null,
        },
      },
};
function catalogPage(query: Query) {
  if (!current.catalog) throw Error("The sample model is unavailable.");
  const targetRows = targets.filter(
    (target) =>
      target.id > query.target_after &&
      `${target.name} ${target.id}`.toLowerCase().includes(query.target_query.toLowerCase()),
  );
  const commandRows = sorted.filter(
    (command) =>
      command.id > query.command_after &&
      `${command.id} ${command.name} ${command.display_name}`
        .toLowerCase()
        .includes(query.command_query.toLowerCase()),
  );
  const catalog = {
    ...current.catalog,
    query,
    selected_command: definitions.find((item) => item.id === query.command) ?? null,
    targets: {
      limit: 25 as const,
      entries: targetRows.slice(0, 25),
      next_after: targetRows.length > 25 ? (targetRows[24]?.id ?? null) : null,
    },
    commands: {
      limit: 25 as const,
      entries: commandRows.slice(0, 25),
      next_after: commandRows.length > 25 ? (commandRows[24]?.id ?? null) : null,
    },
  };
  return {
    catalog,
    spacecraft: spacecraft.filter((craft) =>
      catalog.targets.entries.some((target) => target.spacecraft_id === craft.id),
    ),
  };
}
const initialPage = current;
const port: InstanceType<typeof CommandWorkspace>["$props"]["port"] = {
  navigate: () => {},
  guardNavigation: () => () => {},
  async execute(event, input) {
    if (event === "catalog_page") {
      return { status: "catalog_page", ...catalogPage(readQuery(input.query)) };
    }
    if (event === "browse" && input.kind === "catalog") {
      current = {
        ...current,
        ...catalogPage(readQuery(input.query)),
        draft_preview: null,
        queue_preview: null,
      };
      return { status: "browsed", data: current };
    }
    if (
      event === "preview_targets" &&
      Array.isArray(input.commands) &&
      current.catalog?.selected_command
    ) {
      const definition = current.catalog.selected_command;
      const items = input.commands.map((raw: unknown, index) => {
        if (!record(raw)) throw Error("Invalid sample command");
        const target = targets.find((entry) => entry.id === raw.source_endpoint_ref);
        if (!target || typeof raw.argument_values_json !== "string")
          throw Error("Missing sample target");
        return {
          item_id: `sample_item_${index}`,
          stage_id: current.workbench?.stage.id,
          token: "e".repeat(64),
          new: true,
          order: index,
          command: {
            target,
            revision_id: base.basis.revision_id,
            command_id: definition.id,
            command_name: definition.name,
            command_display_name: definition.display_name,
            actor_id: base.actor_id,
            priority: raw.priority,
            not_before: raw.not_before,
            expires_at: raw.expires_at,
            argument_values_json: raw.argument_values_json,
            resolved_argument_values_json:
              raw.argument_values_json === "{}"
                ? `{${definition.arguments.map((arg) => `${JSON.stringify(arg.name)}:${arg.default_value_json}`).join(",")}}`
                : raw.argument_values_json,
            critical: definition.critical,
            hazardous: definition.hazardous,
            significance: definition.significance,
          },
        };
      });
      current = {
        ...current,
        queue_preview: readQueuePreview(
          {
            token: "8".repeat(64),
            actor_id: base.actor_id,
            requests: items.map((item, index) => ({
              ...item.command,
              token: "9".repeat(64),
              request_id: `sample_request_${index}`,
              requested_at: base.observed_at,
              lifecycle_state:
                definition.hazardous || definition.critical ? "approval_pending" : "validated",
            })),
          },
          base.actor_id,
        ),
        draft_preview: current.workbench
          ? readTargetsPreview(
              {
                token: "d".repeat(64),
                stage_id: current.workbench.stage.id,
                actor_id: base.actor_id,
                notes: input.notes,
                items,
              },
              base.actor_id,
              current.workbench.stage.id,
            )
          : null,
      };
      return {
        status: "previewed",
        preview: current.draft_preview,
        queue_preview: current.queue_preview,
      };
    }
    if (event === "enqueue" && current.queue_preview) {
      const requests = current.queue_preview.requests.map((request) => ({
        request_id: request.request_id,
        target_id: request.target.id,
        requested_at: request.requested_at,
        ...(request.lifecycle_state === "validated"
          ? { state: "queued" as const, queue_id: `queue_${request.request_id}` }
          : { state: "approval_pending" as const, queue_id: null }),
      }));
      current = {
        ...current,
        write_token: "f".repeat(64),
        draft_preview: null,
        queue_preview: null,
        operation: {
          event: "enqueue",
          stage_id: null,
          write_token: current.write_token ?? "c".repeat(64),
          status: "completed",
          receipt: { kind: "enqueue", requests },
        },
      };
      return {
        ...current.operation,
        receipt: { operation: "commands_submitted", actor_id: base.actor_id, requests },
      };
    }
    return {
      status: "rejected",
      feedback:
        "This Storybook example previews local fixture data. Durable writes are available in the Ops workspace.",
    };
  },
};
const readPort = {
  read: async () => ({
    ...current,
    operation:
      current.operation?.status === "completed" && current.operation.receipt.kind === "enqueue"
        ? {
            ...current.operation,
            receipt: {
              operation: "commands_submitted",
              actor_id: base.actor_id,
              requests: current.operation.receipt.requests,
            },
          }
        : current.operation,
  }),
  subscribe: () => () => {},
};
</script>
<template>
  <OpsWorkspaceFrame :context="frameContext">
    <HostPage
      title="Commanding"
      :breadcrumbs="[
        { label: 'Flight Operations', href: '/' },
        { label: 'Kestrel', href: `/missions/${frameContext.mission.mission_id}` },
        { label: 'Commanding' },
      ]"
      workspace
    >
      <CommandWorkspace :page="initialPage" :port="port" :read-port="readPort" />
    </HostPage>
  </OpsWorkspaceFrame>
</template>
