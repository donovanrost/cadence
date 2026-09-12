import type { ReadContext } from "../../shared/read-contracts.ts";
import {
  boolean,
  choice,
  exactHref,
  href,
  identifier,
  integer,
  invalid,
  missionPath,
  navigation,
  record,
  text,
} from "../../shared/read-validation.ts";
import {
  array,
  breadcrumbs,
  id,
  nullable,
  object,
  string,
  unique,
} from "../../shared/form-validation.ts";
import type { Presentation } from "./provider-list.contracts.ts";
import type { ProviderDetailModel } from "./provider-detail.contracts.ts";

const status = object({
  tone: (value) => choice(value, ["info", "ready", "attention", "blocked"]),
  label: string,
});
const detail = object({ label: string, value: string, mono: boolean });
const card = object({ id, title: string, rows: array(detail, 32) });
const action = object({ id, label: string, disabled: boolean });
const profileSection = object({
  id,
  heading: string,
  subtitle: string,
  empty: boolean,
  empty_copy: string,
  table_id: id,
  table_body_id: id,
  columns: array(string, 8),
});

export function readDetail(value: unknown, context: ReadContext): ProviderDetailModel {
  const envelope = record(value);
  const result = object({
    navigation: object({ breadcrumbs: breadcrumbs(context) }),
    provider: object({
      page_id: id,
      display_name: string,
      provider_id: identifier,
      simulated_badge: object({ id, label: string }),
      version: (v) => {
        const s = text(v);
        if (!/^v[1-9][0-9]*$/.test(s)) invalid();
        return s;
      },
      summary_tiles: array(
        object({
          id,
          label: string,
          value: (v) => (typeof v === "number" ? integer(v) : string(v)),
        }),
        12,
      ),
    }),
    actions: object({
      validate: action,
      sync: action,
      archive: object({ id, label: string, disabled: boolean, confirm: (v) => text(v) }),
    }),
    profiles: object({ service: profileSection, delivery: profileSection }),
    details: object({
      configuration: card,
      delivery_policy: card,
      capabilities: object({
        id,
        title: string,
        empty: boolean,
        empty_copy: string,
        items: array(object({ label: string, status }), 64),
      }),
      version_history: object({ id, title: string, stream_id: id }),
    }),
    diagnostics: object({
      id,
      label: string,
      json_id: id,
      rows: array(detail, 32),
      json: (v) => {
        const json = text(v);
        try {
          JSON.parse(json);
        } catch {
          invalid();
        }
        return json;
      },
    }),
    service_profiles: array(
      object({
        __dom_id: id,
        id: identifier,
        display_name: string,
        service_kind: string,
        direction: string,
        data_families: string,
        status,
      }),
    ),
    delivery_profiles: array(
      object({
        __dom_id: id,
        id: identifier,
        display_name: string,
        operator_summary: string,
        delivery_kind: string,
        direction: string,
        status,
      }),
    ),
    provider_versions: array(
      object({ __dom_id: id, version: (v) => integer(v, 1), lifecycle_state: string }),
    ),
  })(envelope.data);
  navigation(
    envelope.navigation,
    context,
    missionPath(context) + "/comms/providers/" + encodeURIComponent(result.provider.provider_id),
  );
  if (
    result.profiles.service.empty !== (result.service_profiles.length === 0) ||
    result.profiles.delivery.empty !== (result.delivery_profiles.length === 0) ||
    result.details.capabilities.empty !== (result.details.capabilities.items.length === 0)
  )
    invalid();
  for (const rows of [result.service_profiles, result.delivery_profiles, result.provider_versions])
    unique(rows.map((row) => row.__dom_id));
  unique(result.service_profiles.map((row) => row.id));
  unique(result.delivery_profiles.map((row) => row.id));
  unique(result.provider_versions.map((row) => String(row.version)));
  if (!result.provider_versions.some((row) => "v" + row.version === result.provider.version))
    invalid();
  return result;
}

export function readList(value: unknown, context: ReadContext): { presentation: Presentation } {
  const envelope = record(value),
    base = missionPath(context) + "/comms/providers";
  navigation(envelope.navigation, context, base);
  const attrs = (value: unknown, links = false): Record<string, string> => {
    const source = record(value);
    if (Object.keys(source).length > 32) invalid();
    return Object.fromEntries(
      Object.entries(source).map(([key, value]) => {
        if (key === "href" && links) return [key, href(value, context)];
        if (key === "data-phx-link" && links) return [key, choice(value, ["redirect"])];
        if (key === "data-phx-link-state" && links) return [key, choice(value, ["push"])];
        if (!["id", "class", "role"].includes(key) && !/^aria-[a-z-]+$/.test(key)) invalid();
        return [key, key === "id" ? id(value) : string(value)];
      }),
    );
  };
  const element = object({ attrs: (v) => attrs(v) });
  const label = object({ attrs: (v) => attrs(v), text: string });
  const link = object({ attrs: (v) => attrs(v, true), text: string });
  const create = object({
    attrs: (v) => {
      const result = attrs(v, true);
      exactHref(result.href, base + "/new", context);
      return result;
    },
    text: string,
    icon: element,
  });
  const result = object({
    presentation: object({
      root: element,
      header: object({
        attrs: (v) => attrs(v),
        body: element,
        content: element,
        breadcrumbs: object({
          attrs: (v) => attrs(v),
          items: array(
            object({
              key: id,
              separator: nullable(label),
              link: nullable(link),
              current: nullable(label),
            }),
            12,
          ),
        }),
        title: object({ attrs: (v) => attrs(v), text: string, suffix: label }),
        subtitle: label,
        actions: object({ attrs: (v) => attrs(v), new_provider: create }),
      }),
      empty_state: nullable(
        object({
          attrs: (v) => attrs(v),
          title: label,
          description: label,
          action_container: element,
          action: create,
        }),
      ),
      card: nullable(
        object({
          attrs: (v) => attrs(v),
          body: element,
          table_component: element,
          rows: array(
            object({
              id,
              display_name: string,
              provider_type: string,
              server_url: string,
              status: (v) => choice(v, ["ready", "attention", "blocked"]),
              status_label: string,
              account_binding: string,
              grant_binding: string,
              last_synced_at: string,
              version: string,
              href: (v) => {
                const path = href(v, context);
                if (
                  !path.startsWith(base + "/") ||
                  /[?#]/.test(path) ||
                  path.slice(base.length + 1).includes("/")
                )
                  invalid();
                return path;
              },
            }),
          ),
        }),
      ),
    }),
  })(envelope.data);
  const presentation = result.presentation;
  if (
    (presentation.empty_state === null) === (presentation.card === null) ||
    (presentation.card && presentation.card.rows.length === 0)
  )
    invalid();
  unique(presentation.header.breadcrumbs.items.map((item) => item.key));
  if (presentation.card) {
    unique(presentation.card.rows.map((row) => row.id));
    unique(presentation.card.rows.map((row) => row.href));
  }
  return result;
}
