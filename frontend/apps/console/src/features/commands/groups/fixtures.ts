import { decode } from "@/api/index.ts";
import { groupReader, type Group } from "./show.ts";

/** Typed group builders for tests (decoded, so they always satisfy the reader). */
export const actor = { actor_kind: "user", user_id: "user-1" };
export const showBody = {
  id: "grp-1",
  state: "approval_pending",
  title: "Reset watchdogs",
  requested_by: actor,
  requested_at: "2026-11-08T02:00:00Z",
  requested_approver_user_id: null,
  member_count: 2,
  target_count: 2,
  command_count: 1,
  second_go_required: true,
  awaiting_me: true,
  operation_id: "op-1",
  review_token: "tok",
  log_entry: "Watchdog drift",
  sent_back_from: null,
  target_query: { chips: [] },
  commands: [
    {
      position: 0,
      command_id: "cmd-1",
      name: "FORCE_WATCHDOG",
      significance: "hazardous",
      critical: false,
      hazardous: true,
      argument_values_json: "{}",
    },
  ],
  release: { not_before: null, expires_at: null, priority: 3 },
  policy: {
    second_go_required: true,
    reasons: [{ key: "hazardous_command", name: "FORCE_WATCHDOG" }],
  },
  decision: null,
  decided_by: null,
  decided_at: null,
  aborted_by: null,
  aborted_at: null,
  abort_reason: null,
  abort_result: null,
  resolved_at: "2026-11-08T02:00:00Z",
  progress: { awaiting_go: 2 },
  events: [
    {
      id: "ev-1",
      kind: "submitted",
      actor,
      at: "2026-11-08T02:00:00Z",
      payload: { members: 2, second_go_required: true },
    },
  ],
  targets_page: { total: 1, unnamed: 0, revision: 1, next_cursor: null },
  events_page: { total: 1, next_cursor: null },
  targets: [
    {
      index: 0,
      spacecraft_id: "sc-1",
      name: "SC-1",
      scid: 7,
      stage: "awaiting_go",
      members: [
        {
          position: 0,
          target_index: 0,
          request_id: "req-1",
          command_id: "cmd-1",
          command_name: "FORCE_WATCHDOG",
          stage: "awaiting_go",
          end_reason: null,
          failure_reason: null,
          verify_by: null,
          occurred_at: null,
        },
      ],
      last_event_at: null,
      blocked: null,
    },
  ],
};

type Raw = Record<string, unknown>;
const isRaw = (v: unknown): v is Raw => typeof v === "object" && v !== null && !Array.isArray(v);
const list = (v: unknown): Raw[] => (Array.isArray(v) ? v.filter(isRaw) : []);

/**
 * A group read for a test. Overridden targets get their `index` (their place) and each member a
 * null `failure_reason` unless the test sets them, and the page totals follow the lists given
 * unless set, so a test names only what it's about (#795).
 */
export function groupOf(overrides: Record<string, unknown> = {}): Group {
  const body: Raw = { ...showBody, ...overrides };
  const targets = list(body["targets"]).map((t, i) => ({
    index: i,
    ...t,
    members: list(t["members"]).map((m) => ({ failure_reason: null, ...m })),
  }));
  const events = list(body["events"]);
  const decoded = decode(groupReader, {
    ...body,
    targets,
    targets_page: overrides["targets_page"] ?? {
      total: targets.length,
      unnamed: targets.filter((t) => !String(Reflect.get(t, "name") ?? "").trim()).length,
      revision: 1,
      next_cursor: null,
    },
    events_page: overrides["events_page"] ?? { total: events.length, next_cursor: null },
  });
  if (!decoded.ok) throw decoded.error;
  return decoded.value;
}
