import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import {
  bounded,
  fail,
  id,
  identity,
  record,
  stageState,
  text,
  time,
  visibility,
  type Identity,
  type StageState,
} from "../../shared/stages/validation";
import { stagesHref, withQuery } from "../../shared/stages/links";
export type StageQuery = { after: string; state: string; query: string };
export type StageEntry = {
  id: string;
  name: string;
  state: StageState;
  visibility: "private" | "shared";
  owner_id: string | null;
};
export type Directory = Identity & {
  observed_at: string;
  query: StageQuery;
  stages: { limit: 25; entries: StageEntry[]; next_after: string | null };
};
export function readDirectory(value: unknown, context: OpsPageContext): Directory {
  bounded(value, 270000);
  const d = value.directory;
  identity(d, context);
  const q = d.query,
    p = d.stages;
  if (
    !time(d.observed_at) ||
    !record(q) ||
    Object.keys(q).length !== 3 ||
    !(q.after === "" || id(q.after)) ||
    !(q.state === "" || stageState(q.state)) ||
    !text(q.query, 240) ||
    !record(p) ||
    p.limit !== 25 ||
    !Array.isArray(p.entries) ||
    p.entries.length > 25
  )
    return fail();
  let previous = q.after as string;
  for (const e of p.entries) {
    if (
      !record(e) ||
      !id(e.id) ||
      e.id <= previous ||
      !text(e.name, 240) ||
      !stageState(e.state) ||
      !visibility(e.visibility) ||
      !(e.owner_id === null || id(e.owner_id)) ||
      (e.visibility === "private" && e.owner_id !== d.actor_id) ||
      (q.state && e.state !== q.state)
    )
      return fail();
    previous = e.id;
  }
  if (
    !(
      p.next_after === null ||
      (id(p.next_after) && p.entries.length === 25 && p.next_after === previous)
    )
  )
    return fail();
  return d as Directory;
}
export function directoryHref(mission: string, query: StageQuery): string {
  if (
    !(query.after === "" || id(query.after)) ||
    !(query.state === "" || stageState(query.state)) ||
    !text(query.query, 240)
  )
    return fail();
  return withQuery(stagesHref(mission), query);
}
