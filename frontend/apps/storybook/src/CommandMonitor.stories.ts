import { required } from "../../../test-support/required";
import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import { ref } from "vue";
import {
  CommandMonitor,
  readCommandMonitor,
  type CommandMonitorModel,
} from "@cadence/commanding/mission-commands";
type CommandObservation = CommandMonitorModel["rows"][number];
const monitorContext = { organizationId: "org-1", missionId: "mission-1" };
function commandObservation(id = "request-a"): CommandObservation {
  return {
    id,
    command_id: "CMD-NOOP",
    name: "NOOP",
    status: "in_flight",
    target: "endpoint-a",
    target_name: "Aurora",
    requested_by: "Operator",
    requested_at: "2026-09-08T12:00:00.123456Z",
    occurred_at: "2026-09-08T12:03:00.654321Z",
    request_state: "released",
    verification_state: "pending",
    queue: {
      id: `queue-${id}`,
      state: "released",
      lane: "endpoint-a",
      enqueued_at: "2026-09-08T12:01:00Z",
    },
    release: {
      id: `release-${id}`,
      queue_entry_id: `queue-${id}`,
      state: "released",
      verification_state: "pending",
      contact_id: "contact-a",
      attempted_at: "2026-09-08T12:02:00Z",
      released_at: "2026-09-08T12:03:00Z",
    },
    verifiers: [
      {
        id: `verifier-${id}`,
        release_attempt_id: `release-${id}`,
        name: "Completion",
        state: "pending",
        matched_at: null,
        timeout_at: "2026-09-08T12:04:00Z",
        matched_record_kind: null,
        matched_record_id: null,
      },
    ],
    verifier_total: 1,
  };
}
function monitorFixture(): CommandMonitorModel {
  return {
    version: 1,
    can_review: true,
    organization_id: "org-1",
    mission_id: "mission-1",
    observed_at: "2026-09-08T12:03:30.123456Z",
    query: { status: "all", target: "all", query: "", page: "1" },
    status: "ready",
    summary: {
      total_count: 1,
      active_count: 1,
      queued_count: 0,
      release_pending_count: 0,
      in_flight_count: 1,
      released_count: 0,
      failed_count: 0,
      indeterminate_count: 0,
    },
    total: 1,
    pages: 1,
    page_size: 25,
    targets: [{ id: "endpoint-a", name: "Aurora" }],
    targets_limited: false,
    rows: [commandObservation()],
    focus: { status: "not_selected", row: null },
  };
}

const meta = {
  title: "Modules/Commanding/Monitor",
  component: CommandMonitor,
  parameters: { layout: "fullscreen" },
  args: {
    model: monitorFixture(),
    context: monitorContext,
    port: { navigate() {} },
    refresh: async () => {},
  },
  render: (args) => ({
    components: { CommandMonitor },
    setup() {
      const model = ref<CommandMonitorModel>(
        readCommandMonitor(JSON.parse(JSON.stringify(args.model)), monitorContext),
      );
      const all = [...model.value.rows],
        destination = ref("");
      const port = {
        navigate(href: string) {
          destination.value = href;
          const query = {
            status: "all",
            target: "all",
            query: "",
            page: "1",
            ...Object.fromEntries(new URL(href, "https://cadence.test").searchParams),
          };
          const rows = all.filter(
            (row) =>
              (query.status === "all" || row.status === query.status) &&
              (query.target === "all" || row.target === query.target) &&
              [row.id, row.name, row.command_id, row.requested_by].some((value) =>
                value?.toLowerCase().includes(query.query.toLowerCase()),
              ),
          );
          const focusId = ("focus_command_id" in query ? query.focus_command_id : undefined) as
            | string
            | undefined;
          const selected = all.find((row) => row.id === focusId);
          model.value = readCommandMonitor(
            {
              ...model.value,
              query,
              status: rows.length ? "ready" : "empty",
              rows,
              total: rows.length,
              pages: 1,
              focus: focusId
                ? selected
                  ? { status: "ready", row: selected }
                  : { status: "not_found", row: null }
                : { status: "not_selected", row: null },
            },
            monitorContext,
          );
        },
      };
      const refresh = async () => {
        model.value = { ...model.value };
      };
      return { model, context: monitorContext, port, refresh, destination };
    },
    template:
      '<div class="p-4 lg:p-6"><CommandMonitor :model="model" :context="context" :port="port" :refresh="refresh" /><p class="mt-6 text-xs text-base-content/75">Fixture-backed projection and navigation. No command operations or live mission reads occur.</p><output aria-label="Requested destination" class="block break-all font-mono text-xs">{{ destination }}</output></div>',
  }),
} satisfies Meta<typeof CommandMonitor>;
export default meta;
type Story = StoryObj<typeof meta>;
export const ReadOnlyProjection: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(required(canvasElement.querySelector("details summary")));
    await expect(
      canvasElement.querySelector('[data-command-verifier="verifier-request-a"]'),
    ).toBeVisible();
  },
};
export const FocusAndFilter: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(
      required(canvasElement.querySelector('[data-command-follow="request-a"]')),
    );
    await expect(canvasElement.querySelector("#command-monitor-focus")).toBeVisible();
    await userEvent.type(
      required(canvasElement.querySelector("#command-monitor-query")),
      "no matching request",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Apply filters" }));
    await expect(canvasElement.querySelector("#command-monitor-empty")).toBeVisible();
    await expect(canvasElement.querySelector("#command-monitor-focus")).toBeVisible();
    await expect(canvas.getByLabelText("Requested destination")).toHaveTextContent(
      "focus_command_id=request-a",
    );
  },
};
const empty = monitorFixture();
empty.rows = [];
empty.total = 0;
empty.status = "empty";
export const EmptyProjection: Story = { args: { model: empty } };
const focused = monitorFixture();
focused.query.focus_command_id = "missing";
focused.focus = { status: "not_found", row: null };
export const MissingFocus: Story = { args: { model: focused } };
