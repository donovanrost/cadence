import type { ReadContext, Collection, Detail } from "../../shared/read-contracts.ts";
import type { TransportRow, TransportDetails } from "./read-contracts.ts";
import {
  collection,
  record,
  identifier,
  text,
  exactHref,
  navigation,
  missionPath,
  integer,
  boolean,
  choice,
  invalid,
} from "../../shared/read-validation.ts";

export function readRow(value: unknown, context: ReadContext): TransportRow {
  const data = record(value),
    id = identifier(data.id);
  return {
    id,
    display_name: text(data.display_name),
    href: exactHref(
      data.href,
      missionPath(context) + "/comms/transports/" + encodeURIComponent(id),
      context,
    ),
    origin: choice(data.origin, ["direct", "provider_managed"]),
    transport_kind: text(data.transport_kind),
    direction_capability: text(data.direction_capability),
    version: integer(data.version, 1),
  };
}
export function readDirectory(value: unknown, context: ReadContext): Collection<TransportRow> {
  return collection(value, context, "transports", readRow);
}
export function readDetail(value: unknown, context: ReadContext): Detail<TransportDetails> {
  const input = record(value),
    data = record(input.data),
    id = identifier(data.id);
  const listHref = missionPath(context) + "/comms/transports",
    detailHref = listHref + "/" + encodeURIComponent(id);
  const origin = choice(data.origin, ["direct", "provider_managed"]);
  const providerManaged = boolean(data.provider_managed);
  if (providerManaged !== (origin === "provider_managed")) return invalid();
  return {
    navigation: navigation(input.navigation, context, detailHref),
    data: {
      id,
      display_name: text(data.display_name),
      href: exactHref(data.href, detailHref, context),
      list_href: exactHref(data.list_href, listHref, context),
      version: integer(data.version, 1),
      lifecycle_state: text(data.lifecycle_state),
      origin,
      transport_kind: text(data.transport_kind),
      direction_capability: text(data.direction_capability),
      provider_managed: providerManaged,
    },
  };
}
