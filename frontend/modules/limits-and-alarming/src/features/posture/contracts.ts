import { state, counts, type State } from "../../shared/states";
export type { State } from "../../shared/states";
import {
  base,
  id,
  page,
  record,
  selection,
  text,
  type Base,
  type Page,
  type Selection,
} from "../../shared/contracts";
export type PostureDocument = Base & {
  surface: "activity";
  states: Page<State>;
  counts: Record<State["severity"], number>;
  spacecraft_filter: string;
  spacecraft: Page<{ id: string; label: string }>;
  selection: Selection;
};
export type PosturePort = { read: () => Promise<unknown>; navigate: (href: string) => void };
export function admitDocument(v: unknown, expected?: unknown): PostureDocument | null {
  if (
    !base(v, "activity", expected) ||
    !record(v) ||
    !counts(v.counts) ||
    !text(v.spacecraft_filter) ||
    !page(
      v.spacecraft,
      (x): x is { id: string; label: string } => record(x) && id(x.id) && text(x.label),
      v.links.self,
    ) ||
    !selection(v.selection, v)
  )
    return null;
  if (
    !page(
      v.states,
      (x): x is State => state(x, v.links.self, v.context.mission_id),
      v.links.self,
    ) ||
    new Set(v.states.items.map((x) => x.id)).size !== v.states.items.length ||
    new Set(v.spacecraft.items.map((x) => x.id)).size !== v.spacecraft.items.length
  )
    return null;
  if (
    v.states.total_count !==
    (v.query.severity
      ? v.counts[v.query.severity as State["severity"]]
      : Object.values(v.counts).reduce((a, b) => Number(a) + Number(b), 0))
  )
    return null;
  if (
    v.states.items.some(
      (x) =>
        (v.query.severity !== "" && x.severity !== v.query.severity) ||
        (v.query.spacecraft !== "" &&
          x.spacecraft_id !== (v.query.spacecraft === "mission" ? null : v.query.spacecraft)),
    )
  )
    return null;
  return v as PostureDocument;
}
