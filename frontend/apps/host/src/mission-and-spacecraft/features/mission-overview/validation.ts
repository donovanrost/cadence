import {
  assertShape,
  bool,
  count,
  href,
  list,
  shape,
  status,
  text,
  tone,
} from "../../shared/validation.ts";
const row = shape({
  id: text,
  __dom_id: text,
  actions_id: text,
  spacecraft_display_name: text,
  spacecraft_id: text,
  scid_label: text,
  endpoint_label: text,
  endpoint_ref_label: text,
  path_label: text,
  path_detail: text,
  status: tone,
  status_label: text,
  issue: text,
  primary_action: text,
  primary_action_href: href,
  view_spacecraft_href: href,
});
const overview = shape({
  overview: shape({
    mission: shape({ eyebrow: text, display_name: text, slug: text }),
    readiness_cards: list(shape({ title: text, value: count, status, description: text })),
    setup: shape({
      eyebrow: text,
      title: text,
      description: text,
      issue_count: count,
      status,
      empty: bool,
      empty_state: shape({ title: text, action_label: text, action_href: href }),
    }),
  }),
  spacecraft_readiness: list(row),
});
export function assertOverview(value: unknown): void {
  assertShape(overview, value);
}
