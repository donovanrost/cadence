import type { SpacecraftPageContext } from "@cadence/plugin-sdk/spacecraft-pages";
import { array, breadcrumbs, id, object, string, unique } from "../../shared/form-validation.ts";
import {
  choice,
  exactHref,
  identifier,
  integer,
  invalid,
  missionPath,
} from "../../shared/read-validation.ts";

export function readSpacecraftRouting(value: unknown, context: SpacecraftPageContext) {
  identifier(context.organizationId);
  const spacecraft = identifier(context.spacecraftId);
  const base = missionPath(context),
    spacecraftPath = base + "/spacecraft/" + encodeURIComponent(spacecraft);
  const result = object({
    page: object({
      title: string,
      subtitle: string,
      breadcrumbs: breadcrumbs(context),
      new_rule: object({
        id,
        label: string,
        href: (v) =>
          exactHref(
            v,
            base + "/comms/routing/new?spacecraft_id=" + encodeURIComponent(spacecraft),
            context,
          ),
      }),
      empty_state: object({ title: string, description: string }),
      rules_id: id,
      rows: array((value) => {
        const row = object({
          id,
          purpose_label: string,
          display_name: string,
          direction: (v) => choice(v, ["INBOUND", "OUTBOUND", "BIDIRECTIONAL"]),
          transport_name: string,
          transport_version: (v) => integer(v, 1),
          role: (v) => choice(v, ["PRIMARY", "CANDIDATE", "CONTRIBUTING"]),
          state: (v) => choice(v, ["ENABLED", "DISABLED"]),
          href: string,
        })(value);
        const prefix = "spacecraft-routing-rule-";
        if (!row.id.startsWith(prefix)) invalid();
        const rule = identifier(row.id.slice(prefix.length));
        exactHref(row.href, base + "/comms/routing/" + encodeURIComponent(rule), context);
        return row;
      }),
    }),
  })(value);
  unique(result.page.rows.map((row) => row.id));
  if (!result.page.breadcrumbs.some((item) => item.href === spacecraftPath)) invalid();
  return result;
}
