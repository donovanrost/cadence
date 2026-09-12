import {
  assertShape,
  bool,
  choice,
  href,
  list,
  nullable,
  shape,
  text,
} from "../../shared/validation.ts";
const status = shape({ tone: choice("ready", "attention", "blocked", "info"), label: text });
const detail = shape({ label: text, value: text });
const action = shape({ label: text, href });
export function assertSpacecraftOverview(value: unknown): void {
  assertShape(
    shape({
      page: shape({
        id: choice("spacecraft-show-page"),
        header: shape({
          title: text,
          breadcrumbs: list(shape({ label: text, href: nullable(href) })),
          title_suffix: shape({ set: bool, label: text }),
        }),
      }),
      profile_binding: shape({
        id: text,
        eyebrow: text,
        bound: bool,
        title: text,
        description: nullable(text),
        version: nullable(text),
        protocols: list(detail),
        status,
        view_profile_href: nullable(href),
        profile_action: action,
      }),
      applications: shape({
        id: text,
        list_id: text,
        visible: bool,
        title: text,
        description: text,
        empty: bool,
        empty_state: text,
        rows: list(
          shape({
            id: text,
            application_key: text,
            display_name: text,
            status,
            manage_href: nullable(href),
          }),
        ),
        view_action: action,
      }),
      workflow_cards: list(
        shape({ id: text, title: text, value: text, description: text, status, action }),
      ),
      overview: shape({
        title: text,
        scid: detail,
        display_name: detail,
        spacecraft_id: detail,
        mission: shape({ label: text, value: text, href }),
        organization_id: detail,
        metadata_json: nullable(text),
      }),
    }),
    value,
  );
}
