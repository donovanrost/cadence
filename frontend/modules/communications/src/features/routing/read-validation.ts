import type { ReadContext, Collection, Detail } from "../../shared/read-contracts.ts";
import type { RoutingRow, RoutingDetails } from "./read-contracts.ts";
import {
  collection,
  record,
  identifier,
  text,
  exactHref,
  navigation,
  missionPath,
  boolean,
  integer,
} from "../../shared/read-validation.ts";

export function readRow(value: unknown, context: ReadContext): RoutingRow {
  const data = record(value),
    id = identifier(data.id);
  return {
    id,
    display_name: text(data.display_name),
    href: exactHref(
      data.href,
      missionPath(context) + "/comms/routing/" + encodeURIComponent(id),
      context,
    ),
    spacecraft_id: identifier(data.spacecraft_id),
    spacecraft_name: text(data.spacecraft_name),
    purpose_label: text(data.purpose_label),
    direction: text(data.direction),
    transport_id: identifier(data.transport_id),
    transport_name: text(data.transport_name),
    role: text(data.role),
    enabled: boolean(data.enabled),
  };
}
export function readDirectory(value: unknown, context: ReadContext): Collection<RoutingRow> {
  return collection(value, context, "routing", readRow);
}
export function readDetail(value: unknown, context: ReadContext): Detail<RoutingDetails> {
  const input = record(value),
    data = record(input.data),
    id = identifier(data.id);
  const listHref = missionPath(context) + "/comms/routing",
    detailHref = listHref + "/" + encodeURIComponent(id);
  return {
    navigation: navigation(input.navigation, context, detailHref),
    data: {
      id,
      display_name: text(data.display_name),
      href: exactHref(data.href, detailHref, context),
      list_href: exactHref(data.list_href, listHref, context),
      enabled: boolean(data.enabled),
      lifecycle_state: text(data.lifecycle_state),
      spacecraft_id: identifier(data.spacecraft_id),
      spacecraft_name: text(data.spacecraft_name),
      purpose_label: text(data.purpose_label),
      direction: text(data.direction),
      transport_id: identifier(data.transport_id),
      transport_name: text(data.transport_name),
      transport_version: integer(data.transport_version, 1),
      role: text(data.role),
    },
  };
}
