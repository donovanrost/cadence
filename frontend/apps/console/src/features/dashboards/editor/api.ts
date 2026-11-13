import { decode, request, type ApiError, type ApiResult } from "@/api";
import type { Runtime } from "../api.ts";
import {
  commandFailure,
  compareReply,
  copiedReply,
  notReady,
  previewReply,
  rebaseReply,
  savedReply,
  versionConflict,
  versionsReply,
  type Command,
  type CommandCode,
  type Preview,
  type Rebase,
  type Versions,
} from "./contracts.ts";
import type { Draft } from "./draft.ts";

/** D7–D13 under `/missions/:m/dashboards/:id` (plans/dashboards.md; api builds on StatelessAuthoring). */

const base = (missionId: string, dashboardId: string) =>
  `/missions/${encodeURIComponent(missionId)}/dashboards/${encodeURIComponent(dashboardId)}`;
const wireRuntime = (r: Runtime) => ({
  from: r.from || null,
  to: r.to || null,
  spacecraft_id: r.spacecraftId || null,
});
const wireDraft = (draft: Draft) => ({ base_version: draft.baseVersion, commands: draft.commands });
const opts = (body: unknown, signal?: AbortSignal) =>
  signal ? { method: "POST" as const, body, signal } : { method: "POST" as const, body };

export function preview(
  missionId: string,
  dashboardId: string,
  draft: Draft,
  runtime: Runtime,
  signal?: AbortSignal,
): Promise<ApiResult<Preview>> {
  return request(
    `${base(missionId, dashboardId)}/preview`,
    previewReply,
    opts({ ...wireDraft(draft), runtime: wireRuntime(runtime) }, signal),
  );
}

export function save(
  missionId: string,
  dashboardId: string,
  draft: Draft,
  input: Readonly<{
    message: string;
    defaults: { time: boolean; scope: boolean };
    runtime: Runtime;
  }>,
) {
  return request(
    `${base(missionId, dashboardId)}/save`,
    savedReply,
    opts({
      ...wireDraft(draft),
      message: input.message.trim() || null,
      defaults: input.defaults,
      runtime: wireRuntime(input.runtime),
    }),
  );
}

export function rebase(
  missionId: string,
  dashboardId: string,
  draft: Draft,
  runtime: Runtime,
): Promise<ApiResult<Rebase>> {
  return request(
    `${base(missionId, dashboardId)}/rebase`,
    rebaseReply,
    opts({ ...wireDraft(draft), runtime: wireRuntime(runtime) }),
  );
}

export function copy(missionId: string, dashboardId: string, draft: Draft, name: string) {
  return request(
    `${base(missionId, dashboardId)}/copy`,
    copiedReply,
    opts({ ...wireDraft(draft), name }),
  );
}

export function fetchVersions(
  missionId: string,
  dashboardId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Versions>> {
  return request(
    `${base(missionId, dashboardId)}/versions`,
    versionsReply,
    signal ? { signal } : {},
  );
}

export function compareVersions(missionId: string, dashboardId: string, from: number, to: number) {
  return request(
    `${base(missionId, dashboardId)}/versions/compare?from=${from}&to=${to}`,
    compareReply,
  );
}

export function restore(missionId: string, dashboardId: string, version: number, expected: number) {
  return request(
    `${base(missionId, dashboardId)}/versions/${version}/restore`,
    savedReply,
    opts({ expected_version: expected }),
  );
}

/** What an editor write's failure means for the draft. Unknown failures stay generic. */
export type EditFailure =
  | {
      kind: "command";
      index: number;
      command: Command | null;
      code: CommandCode;
      field: string | null;
    }
  | {
      kind: "conflict";
      currentVersion: number;
      savedBy: string | null;
      savedAt: string | null;
    }
  | {
      kind: "not_ready";
      placements: readonly { placement_id: string | null; code: string; message: string }[];
    }
  | { kind: "too_many_commands" }
  | { kind: "other"; error: ApiError };

export function editFailure(error: ApiError, draft: Draft): EditFailure {
  if (error.kind === "conflict" && error.code === "version_conflict") {
    const c = decode(versionConflict, error.details);
    if (c.ok)
      return {
        kind: "conflict",
        currentVersion: c.value.current_version,
        savedBy: c.value.saved_by?.name ?? null,
        savedAt: c.value.saved_at,
      };
  }
  if (error.kind === "invalid" && error.code === "invalid_command") {
    const c = decode(commandFailure, error.details);
    if (c.ok)
      return {
        kind: "command",
        index: c.value.index,
        command: draft.commands[c.value.index] ?? null,
        code: c.value.code,
        field: c.value.field,
      };
  }
  if (error.kind === "invalid" && error.code === "dashboard_not_ready") {
    const n = decode(notReady, error.details);
    if (n.ok) return { kind: "not_ready", placements: n.value.placements };
  }
  if (error.kind === "invalid" && error.code === "too_many_commands")
    return { kind: "too_many_commands" };
  return { kind: "other", error };
}
