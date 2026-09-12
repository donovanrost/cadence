import {
  assertShape,
  attrs,
  bool,
  choice,
  count,
  href,
  list,
  nullable,
  shape,
  text,
} from "../../shared/validation.ts";
const element = shape({ attrs });
const label = shape({ attrs, text });
const status = choice("ready", "attention");
const positive = (value: unknown) => count(value) && Number(value) > 0;
const directory = shape({
  presentation: shape({
    root: element,
    header: shape({ attrs, body: element, content: element, title: label, subtitle: label }),
    breadcrumbs: shape({ attrs, items: list(shape({ label: text, href: nullable(href) })) }),
    summary_tiles: list(
      shape({ id: text, label: text, value: count, href, active: bool, warning: bool }),
    ),
    roster: shape({
      href,
      filter: text,
      fleet_empty: bool,
      subtitle: text,
      new_spacecraft_href: href,
      search: text,
      sort_by: choice("display_name", "scid"),
      sort_dir: choice("asc", "desc"),
      filtered_empty: bool,
      page: positive,
      page_size: positive,
      total_count: count,
      pagination_visible: bool,
      range_label: text,
      previous_page: positive,
      next_page: positive,
      previous_disabled: bool,
      next_disabled: bool,
      rows: list(
        shape({
          id: text,
          actions_id: text,
          display_name: text,
          scid_label: text,
          scid_missing: bool,
          profile_label: text,
          status,
          status_label: text,
          href,
          identity_href: href,
        }),
      ),
    }),
    profiles: shape({
      empty: bool,
      truncated: bool,
      subtitle: text,
      new_profile_href: href,
      all_profiles_href: href,
      rows: list(
        shape({
          id: text,
          display_name: text,
          href,
          fleet_entries: list(shape({ label: text, href: nullable(href) })),
          protocols: text,
          applications: text,
          status,
          status_label: text,
        }),
      ),
    }),
  }),
});
export function assertSpacecraftDirectory(value: unknown): void {
  assertShape(directory, value);
}
