import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { readDirectory, type Directory } from "@cadence/commanding/command-stages";
import {
  readWorkbench,
  readBatchPreview,
  readItemPreview,
  type Workbench,
  type BatchPreview,
  type ItemPreview,
} from "@cadence/commanding/stage-workbench";
import { readCommandMonitor, type CommandMonitorModel } from "@cadence/commanding/mission-commands";
import { readCatalog, targetBasis, type Catalog } from "../../shared/command-draft/contracts";
import {
  bounded,
  digest,
  fail,
  id,
  nullableText,
  order,
  record,
  text,
  time,
} from "../../shared/stages/validation";
import { readOperation, type RequestReceipt } from "../../shared/stages/operations";
import {
  readQueuePreview,
  readEnqueueReceipt,
  type QueuePreview,
  type EnqueueReceipt,
} from "./queue-contracts";

export const writeEvents = [
  "create_stage",
  "save_targets",
  "enqueue",
  "submit",
  "cancel_item",
  "edit_details",
] as const;
export type WriteEvent = (typeof writeEvents)[number];
export type WorkspaceReceipt =
  | { kind: "stage"; name: string }
  | { kind: "drafts"; items: readonly { item_id: string; updated_at: string }[] }
  | { kind: "requests"; requests: readonly RequestReceipt[] }
  | { kind: "enqueue"; requests: readonly EnqueueReceipt[] }
  | { kind: "item"; item_id: string };
export type WorkspaceOperation = Readonly<{
  write_token: string;
}> &
  (
    | { event: "enqueue"; stage_id: null }
    | { event: Exclude<WriteEvent, "enqueue">; stage_id: string }
  ) &
  (
    | { status: "unconfirmed" }
    | { status: "rejected"; feedback: string }
    | { status: "completed"; receipt: WorkspaceReceipt }
  );
export type TargetsPreview = Readonly<{
  token: string;
  stage_id: string;
  actor_id: string;
  notes: string | null;
  items: readonly (ItemPreview & { order: number })[];
}>;
export type WorkspacePreparation = Readonly<{
  state: "prepare";
  initial_shelf: "expanded" | "minimized";
  directory: Directory;
  catalog: Catalog | null;
  spacecraft: readonly { id: string; name: string }[];
  workbench: Workbench | null;
  new_stage_id: string;
  write_token: string | null;
  operation: WorkspaceOperation | null;
  draft_preview: TargetsPreview | null;
  queue_preview: QueuePreview | null;
  batch_preview: BatchPreview | null;
  monitor: CommandMonitorModel;
}>;
export type WorkspaceObservation = Readonly<{ state: "observe"; monitor: CommandMonitorModel }>;
export type WorkspacePage = WorkspacePreparation | WorkspaceObservation;

function readSpacecraft(value: unknown, catalog: Catalog | null) {
  if (!Array.isArray(value) || value.length > 25) return fail();
  const seen = new Set<string>();
  return value.map((row: unknown) => {
    if (
      !record(row) ||
      !id(row.id) ||
      !text(row.name, 4096) ||
      seen.has(row.id) ||
      !catalog?.targets.entries.some((target) => target.spacecraft_id === row.id)
    )
      return fail();
    seen.add(row.id);
    return { id: row.id, name: row.name };
  });
}

export function readCatalogPage(value: unknown, context: OpsPageContext, actor: string) {
  bounded(value, 262_144);
  if (value.status !== "catalog_page") return fail();
  const catalog = readCatalog(value.catalog, context);
  if (catalog.actor_id !== actor) return fail();
  return { catalog, spacecraft: readSpacecraft(value.spacecraft, catalog) };
}

export function readWorkspaceOperation(value: unknown, actor: string): WorkspaceOperation {
  if (!record(value) || !digest(value.write_token) || !writeEvents.some((e) => e === value.event))
    return fail();
  const event = writeEvents.find((e) => e === value.event);
  if (!event) return fail();
  if (event === "enqueue") {
    if (value.stage_id !== null) return fail();
    const base = { event: "enqueue" as const, stage_id: null, write_token: value.write_token };
    if (value.status === "unconfirmed") return { ...base, status: "unconfirmed" };
    if (value.status === "rejected" && text(value.feedback))
      return { ...base, status: "rejected", feedback: value.feedback };
    if (value.status === "completed")
      return {
        ...base,
        status: "completed",
        receipt: { kind: "enqueue", requests: readEnqueueReceipt(value.receipt, actor) },
      };
    return fail();
  }
  if (!id(value.stage_id)) return fail();
  const base = { event, stage_id: value.stage_id, write_token: value.write_token };
  if (value.status === "unconfirmed") return { ...base, status: "unconfirmed" };
  if (value.status === "rejected" && text(value.feedback))
    return { ...base, status: "rejected", feedback: value.feedback };
  if (value.status !== "completed") return fail();
  const receipt = value.receipt;
  if (event === "save_targets") {
    if (
      !record(receipt) ||
      receipt.operation !== "items_created" ||
      receipt.stage_id !== base.stage_id ||
      receipt.actor_id !== actor ||
      !Array.isArray(receipt.items) ||
      receipt.items.length < 1 ||
      receipt.items.length > 25
    )
      return fail();
    const seen = new Set<string>();
    const items = receipt.items.map((item: unknown) => {
      if (!record(item) || !id(item.item_id) || !time(item.updated_at) || seen.has(item.item_id))
        return fail();
      seen.add(item.item_id);
      return { item_id: item.item_id, updated_at: item.updated_at };
    });
    return { ...base, status: "completed", receipt: { kind: "drafts", items } };
  }
  const result = readOperation(
    { ...value, event: event === "create_stage" ? "create" : event },
    actor,
    base.stage_id,
  );
  if (result.status !== "completed") return fail();
  const r = result.receipt;
  if (event === "create_stage" && r.name !== undefined)
    return { ...base, status: "completed", receipt: { kind: "stage", name: r.name } };
  if (event === "submit" && r.requests)
    return { ...base, status: "completed", receipt: { kind: "requests", requests: r.requests } };
  if ((event === "cancel_item" || event === "edit_details") && r.item_id)
    return { ...base, status: "completed", receipt: { kind: "item", item_id: r.item_id } };
  return fail();
}

export function readTargetsPreview(value: unknown, actor: string, stage: string): TargetsPreview {
  if (
    !record(value) ||
    !digest(value.token) ||
    value.stage_id !== stage ||
    value.actor_id !== actor ||
    !nullableText(value.notes) ||
    !Array.isArray(value.items) ||
    value.items.length < 1 ||
    value.items.length > 25
  )
    return fail();
  const items = new Set<string>(),
    targets = new Set<string>();
  let lastOrder = -1;
  const entries = value.items.map((raw: unknown) => {
    const item = readItemPreview(raw, actor, stage, null, null);
    if (
      !record(raw) ||
      !order(raw.order) ||
      raw.order <= lastOrder ||
      items.has(item.item_id) ||
      targets.has(item.command.target.id)
    )
      return fail();
    lastOrder = raw.order;
    items.add(item.item_id);
    targets.add(item.command.target.id);
    return { ...item, order: raw.order };
  });
  if (
    new Set(entries.map((item) => item.command.command_id)).size !== 1 ||
    new Set(entries.map((item) => item.command.revision_id)).size !== 1
  )
    return fail();
  return {
    token: value.token,
    stage_id: stage,
    actor_id: actor,
    notes: value.notes,
    items: entries,
  };
}

export function readWorkspace(value: unknown, context: OpsPageContext): WorkspacePage {
  bounded(value, 2_000_000);
  const monitor = readCommandMonitor(value.monitor, context);
  if (value.state === "observe") return { state: "observe", monitor };
  if (
    value.state !== "prepare" ||
    (value.initial_shelf !== "expanded" && value.initial_shelf !== "minimized")
  )
    return fail();
  const directory = readDirectory({ directory: value.directory }, context);
  const catalog = value.catalog === null ? null : readCatalog(value.catalog, context);
  const workbench = value.workbench === null ? null : readWorkbench(value.workbench, context);
  const actor = directory.actor_id;
  if (
    (catalog && catalog.actor_id !== actor) ||
    (workbench && workbench.actor_id !== actor) ||
    !id(value.new_stage_id) ||
    !(value.write_token === null || digest(value.write_token))
  )
    return fail();
  const spacecraft = readSpacecraft(value.spacecraft, catalog);
  const operation =
    value.operation === null ? null : readWorkspaceOperation(value.operation, actor);
  if (operation?.status === "unconfirmed" && value.write_token !== null) return fail();
  const draft =
    value.draft_preview === null
      ? null
      : workbench
        ? readTargetsPreview(value.draft_preview, actor, workbench.stage.id)
        : fail();
  const queue = value.queue_preview === null ? null : readQueuePreview(value.queue_preview, actor);
  if (
    operation?.status !== "unconfirmed" &&
    queue &&
    (!catalog ||
      queue.requests.some(
        (request) =>
          request.command_id !== catalog.selected_command?.id ||
          request.revision_id !== targetBasis(catalog, request.target.id)?.revision_id,
      ))
  )
    return fail();
  const batch =
    value.batch_preview === null
      ? null
      : workbench
        ? readBatchPreview(value.batch_preview, actor, workbench.stage.id)
        : fail();
  if (
    operation?.status !== "unconfirmed" &&
    draft &&
    (!catalog ||
      draft.items.some(
        (item) =>
          item.command.command_id !== catalog.selected_command?.id ||
          item.command.revision_id !== targetBasis(catalog, item.command.target.id)?.revision_id,
      ))
  )
    return fail();
  return {
    state: "prepare",
    initial_shelf: value.initial_shelf,
    directory,
    catalog,
    spacecraft,
    workbench,
    new_stage_id: value.new_stage_id,
    write_token: value.write_token,
    operation,
    draft_preview: draft,
    queue_preview: queue,
    batch_preview: batch,
    monitor,
  };
}

export function workspaceHref(mission: string, stage?: string) {
  if (!id(mission) || (stage !== undefined && !id(stage))) return fail();
  return `/missions/${encodeURIComponent(mission)}/ops/commands/workspace${stage ? `?stage=${encodeURIComponent(stage)}` : ""}`;
}
