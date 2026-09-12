import type { OpsContactRequirementListProps } from "./OpsContactRequirementList.contracts";

const states = ["all", "active", "closed", "canceled"] as const;
const record = (value: unknown): value is Record<string, any> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const text = (value: unknown, max = 2048): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= max;
const id = (value: unknown): value is string =>
  text(value, 256) &&
  new TextEncoder().encode(value).length <= 256 &&
  !/[\u0000-\u0020\u007f]/.test(value);
const domId = (value: unknown) => text(value, 400) && /^[a-zA-Z][a-zA-Z0-9_-]*$/.test(value);
const texts = (value: unknown, keys: string[]) =>
  record(value) && keys.every((key) => text(value[key]));
const segment = (value: string) =>
  encodeURIComponent(value).replace(
    /[!'()*]/g,
    (char) => "%" + char.charCodeAt(0).toString(16).toUpperCase(),
  );
const pageHref = (base: string, page: number, state: string) =>
  base + "?page=" + page + "&state=" + state;

/** Reject incompatible or structurally unsafe data before rendering any links. */
export function admitRequirementList(value: unknown): value is OpsContactRequirementListProps {
  try {
    if (
      !record(value) ||
      value.contract_version !== 1 ||
      !record(value.context) ||
      !id(value.context.organization_id) ||
      !id(value.context.mission_id) ||
      !record(value.query) ||
      !Number.isSafeInteger(value.query.page) ||
      value.query.page < 1 ||
      value.query.page > 1_000_000 ||
      !states.includes(value.query.state) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 131_072
    )
      return false;
    const base = "/missions/" + segment(value.context.mission_id) + "/ops/requirements";
    const page = value.page;
    if (
      !record(page) ||
      !domId(page.id) ||
      !domId(page.list_id) ||
      !texts(page.header, ["eyebrow", "title", "description"]) ||
      !record(page.header.create_action) ||
      !domId(page.header.create_action.id) ||
      !text(page.header.create_action.label) ||
      page.header.create_action.href !== base + "/new" ||
      !texts(page.empty_state, ["id", "title", "description"]) ||
      !domId(page.empty_state.id) ||
      !Array.isArray(page.journey_steps) ||
      page.journey_steps.length > 4 ||
      !page.journey_steps.every(
        (step: unknown) =>
          texts(step, ["number", "label", "detail"]) &&
          typeof (step as Record<string, unknown>).active === "boolean",
      )
    )
      return false;
    if (
      !Array.isArray(value.filters) ||
      value.filters.length !== 4 ||
      !value.filters.every(
        (filter: unknown, index: number) =>
          record(filter) &&
          filter.id === "requirements-filter-" + states[index] &&
          text(filter.label) &&
          filter.href === pageHref(base, 1, states[index]!) &&
          filter.active === (states[index] === value.query.state),
      )
    )
      return false;
    const pagination = value.pagination;
    if (
      !record(pagination) ||
      pagination.label !== "Page " + value.query.page ||
      pagination.previous_href !==
        (value.query.page > 1 ? pageHref(base, value.query.page - 1, value.query.state) : null) ||
      !(
        pagination.next_href === null ||
        pagination.next_href === pageHref(base, value.query.page + 1, value.query.state)
      )
    )
      return false;
    if (!Array.isArray(value.requirements) || value.requirements.length > 25) return false;
    const reservedIds = [
      page.id,
      page.list_id,
      page.empty_state.id,
      page.header.create_action.id,
      "requirements-previous-page",
      "requirements-next-page",
      ...value.filters.map((filter: any) => filter.id),
    ];
    const identities = new Set<string>(),
      domIds = new Set<string>(reservedIds);
    if (domIds.size !== reservedIds.length) return false;
    for (const row of value.requirements) {
      if (
        !record(row) ||
        !id(row.id) ||
        !domId(row.__dom_id) ||
        identities.has(row.id) ||
        domIds.has(row.__dom_id) ||
        !texts(row, ["version_direction", "intent_label", "outcome_detail"]) ||
        !texts(row.window, ["label", "detail"]) ||
        !texts(row.lifecycle, ["label", "detail"]) ||
        !["Active", "Closed", "Canceled"].includes(row.lifecycle.label) ||
        !texts(row.priority, ["label", "tone", "class"]) ||
        !["error", "warning", "neutral"].includes(row.priority.tone) ||
        row.priority.class !== "text-" + row.priority.tone ||
        row.detail_href !== base + "/" + segment(row.id)
      )
        return false;
      identities.add(row.id);
      domIds.add(row.__dom_id);
    }
    return true;
  } catch {
    return false;
  }
}
