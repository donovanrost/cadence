import { detailsOf, isError, request, type ApiError, type ApiResult } from "@/api";
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
      index: number | null;
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
  const conflict = isError(error, "version_conflict") ? detailsOf(error, versionConflict) : null;
  if (conflict)
    return {
      kind: "conflict",
      currentVersion: conflict.current_version,
      savedBy: conflict.saved_by?.name ?? null,
      savedAt: conflict.saved_at,
    };
  const refused = isError(error, "invalid_command") ? detailsOf(error, commandFailure) : null;
  if (refused)
    return {
      kind: "command",
      index: refused.index,
      command: refused.index === null ? null : (draft.commands[refused.index] ?? null),
      code: refused.code,
      field: refused.field,
    };
  const unready = isError(error, "dashboard_not_ready") ? detailsOf(error, notReady) : null;
  if (unready) return { kind: "not_ready", placements: unready.placements };
  if (isError(error, "too_many_commands")) return { kind: "too_many_commands" };
  return { kind: "other", error };
}
