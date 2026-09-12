import { parseArgumentValues } from "../../shared/command-draft/exact-values";
import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import {
  readCatalog,
  readCommandSemantics,
  readPreview,
  type Catalog,
  type Preview,
  type Query,
} from "../../shared/command-draft/contracts";
import { readOperation, type Operation } from "../../shared/stages/operations";
import {
  bounded,
  digest,
  fail,
  id,
  identity,
  nullableText,
  order,
  record,
  stageState,
  text,
  time,
  visibility,
  type Identity,
  type StageState,
} from "../../shared/stages/validation";
import { stagesHref, withQuery } from "../../shared/stages/links";
export type Stage = {
  id: string;
  expected_stage: string;
  name: string;
  description: string | null;
  visibility: "private" | "shared";
  state: StageState;
  owner_id: string | null;
  can_edit_items: boolean;
  can_edit_stage: boolean;
};
export type Item = {
  id: string;
  expected_item: string;
  command_id: string;
  revision_id: string;
  target_id: string;
  order: number;
  state: "draft" | "submitted" | "canceled";
  priority: number;
  not_before: string | null;
  expires_at: string | null;
  request_id: string | null;
  notes: string | null;
  available: boolean;
  argument_values_json: string | null;
};
export type WorkbenchQuery = { after: string; after_order: string; item: string; state: string };
export type Workbench = Identity<2> & {
  observed_at: string;
  stage: Stage;
  query: WorkbenchQuery;
  items: { limit: 25; entries: Item[]; next_after: { id: string; order: number } | null };
  selected_item: Item | null;
};
export type DraftCommand = Omit<
  Preview,
  "token" | "request_id" | "lifecycle_state" | "requested_at"
>;
export type ItemPreview = {
  token: string;
  item_id: string;
  stage_id: string;
  new: boolean;
  command: DraftCommand;
};
export type BatchPreview = {
  token: string;
  stage_id: string;
  actor_id: string;
  requests: (Preview & { item_id: string; notes: string | null; order: number })[];
};
export type WorkbenchPage = {
  workbench: Workbench;
  catalog: Catalog | null;
  write_token: string | null;
  operation: Operation | null;
  notice: string | null;
  item_preview: ItemPreview | null;
  batch_preview: BatchPreview | null;
};
const args = (v: unknown): v is string => {
  try {
    parseArgumentValues(v);
    return true;
  } catch {
    return false;
  }
};
function readItem(v: unknown, selected: boolean): Item {
  if (
    !record(v) ||
    Object.hasOwn(v, "argument_values") ||
    !id(v.id) ||
    !digest(v.expected_item) ||
    !id(v.command_id) ||
    !id(v.revision_id) ||
    !id(v.target_id) ||
    !order(v.order) ||
    !order(v.priority) ||
    !["draft", "submitted", "canceled"].includes(String(v.state)) ||
    ![v.not_before, v.expires_at].every((x) => x === null || time(x)) ||
    !nullableText(v.notes) ||
    typeof v.available !== "boolean" ||
    !(v.request_id === null || id(v.request_id))
  )
    return fail();
  if ((v.state === "submitted") !== (v.request_id !== null)) return fail();
  if (selected && v.available ? !args(v.argument_values_json) : v.argument_values_json !== null)
    return fail();
  return v as Item;
}
export function readItemPreview(
  v: unknown,
  actor: string,
  stage: string,
  catalog: Catalog | null,
  selected: Item | null,
): ItemPreview {
  if (
    !record(v) ||
    !digest(v.token) ||
    !id(v.item_id) ||
    v.stage_id !== stage ||
    typeof v.new !== "boolean" ||
    !record(v.command) ||
    (selected ? v.new || v.item_id !== selected.id : !v.new)
  )
    return fail();
  // The draft preview shares command semantics, but has no formal request identity.
  const command = readCommandSemantics(v.command, { actor_id: actor });
  if (
    catalog &&
    (command.revision_id !== catalog.basis.revision_id ||
      command.command_id !== catalog.query.command ||
      command.target.id !== catalog.query.target)
  )
    return fail();
  return v as ItemPreview;
}
export function readBatchPreview(v: unknown, actor: string, stage: string): BatchPreview {
  if (
    !record(v) ||
    !digest(v.token) ||
    v.stage_id !== stage ||
    v.actor_id !== actor ||
    !Array.isArray(v.requests) ||
    v.requests.length < 1 ||
    v.requests.length > 25
  )
    return fail();
  const requests = new Set(),
    items = new Set();
  let previousOrder = -1,
    previousId = "";
  for (const r of v.requests) {
    const p = readPreview(r, { actor_id: actor });
    if (
      !record(r) ||
      p.token !== v.token ||
      !id(r.item_id) ||
      !nullableText(r.notes) ||
      !order(r.order) ||
      items.has(r.item_id) ||
      requests.has(p.request_id) ||
      r.order < previousOrder ||
      (r.order === previousOrder && r.item_id <= previousId)
    )
      return fail();
    items.add(r.item_id);
    requests.add(p.request_id);
    previousOrder = r.order;
    previousId = r.item_id;
  }
  return v as BatchPreview;
}
export function readWorkbenchPage(value: unknown, context: OpsPageContext): WorkbenchPage {
  bounded(value, 1200000);
  const w = value.workbench;
  identity(w, context, 2);
  const s = w.stage,
    q = w.query,
    p = w.items;
  if (
    !record(s) ||
    !id(s.id) ||
    (context.resourceId && context.resourceId !== s.id) ||
    !digest(s.expected_stage) ||
    !text(s.name, 240) ||
    !nullableText(s.description) ||
    !visibility(s.visibility) ||
    !stageState(s.state) ||
    !(s.owner_id === null || id(s.owner_id)) ||
    typeof s.can_edit_items !== "boolean" ||
    typeof s.can_edit_stage !== "boolean" ||
    !time(w.observed_at)
  )
    return fail();
  const editable = ["draft", "in_review", "ready_to_submit"].includes(s.state);
  if (
    (s.visibility === "private" && s.owner_id !== w.actor_id) ||
    s.can_edit_items !== editable ||
    s.can_edit_stage !== (editable && s.owner_id === w.actor_id)
  )
    return fail();
  if (
    !record(q) ||
    Object.keys(q).length !== 4 ||
    !(q.after === "" || id(q.after)) ||
    !(q.item === "" || id(q.item)) ||
    !["", "draft", "submitted", "canceled"].includes(String(q.state)) ||
    typeof q.after_order !== "string" ||
    (q.after === ""
      ? q.after_order !== ""
      : !/^(0|[1-9]\d*)$/.test(q.after_order) || !order(Number(q.after_order)))
  )
    return fail();
  if (!record(p) || p.limit !== 25 || !Array.isArray(p.entries) || p.entries.length > 25)
    return fail();
  let previousOrder = q.after === "" ? -1 : Number(q.after_order),
    previousId = q.after as string;
  const ids = new Set();
  for (const raw of p.entries) {
    const item = readItem(raw, false);
    if (
      ids.has(item.id) ||
      item.order < previousOrder ||
      (item.order === previousOrder && item.id <= previousId) ||
      (q.state && item.state !== q.state)
    )
      return fail();
    ids.add(item.id);
    previousOrder = item.order;
    previousId = item.id;
  }
  if (
    p.next_after !== null &&
    (!record(p.next_after) ||
      p.entries.length !== 25 ||
      p.next_after.id !== previousId ||
      p.next_after.order !== previousOrder)
  )
    return fail();
  const selected = w.selected_item === null ? null : readItem(w.selected_item, true);
  if (selected && selected.id !== q.item) return fail();
  const catalog = value.catalog === null ? null : readCatalog(value.catalog, context);
  if (catalog && catalog.actor_id !== w.actor_id) return fail();
  if (!(value.write_token === null || digest(value.write_token)) || !nullableText(value.notice))
    return fail();
  const operation =
    value.operation === null ? null : readOperation(value.operation, w.actor_id, s.id);
  if (
    operation?.event === "create" ||
    (operation?.status === "unconfirmed" && value.write_token !== null)
  )
    return fail();
  const itemPreview =
    value.item_preview === null
      ? null
      : readItemPreview(value.item_preview, w.actor_id, s.id, catalog, selected);
  const batchPreview =
    value.batch_preview === null ? null : readBatchPreview(value.batch_preview, w.actor_id, s.id);
  return {
    workbench: w as Workbench,
    catalog,
    write_token: value.write_token as string | null,
    operation,
    notice: value.notice as string | null,
    item_preview: itemPreview,
    batch_preview: batchPreview,
  };
}
export const emptyCatalogQuery = (): Query => ({
  command: "",
  target: "",
  command_after: "",
  target_after: "",
  command_query: "",
  target_query: "",
});
export function workbenchHref(
  mission: string,
  stage: string,
  query: WorkbenchQuery,
  catalog: Query = emptyCatalogQuery(),
): string {
  return withQuery(stagesHref(mission, stage), { ...query, ...catalog });
}
