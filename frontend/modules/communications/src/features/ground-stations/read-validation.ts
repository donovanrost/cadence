import type { ReadContext, Collection, Detail } from "../../shared/read-contracts.ts";
import type { GroundStationRow, GroundStationDetails } from "./read-contracts.ts";
import {
  collection,
  record,
  identifier,
  text,
  exactHref,
  navigation,
  missionPath,
} from "../../shared/read-validation.ts";

export function readRow(value: unknown, context: ReadContext): GroundStationRow {
  const data = record(value),
    id = identifier(data.id);
  return {
    id,
    display_name: text(data.display_name),
    href: exactHref(
      data.href,
      missionPath(context) + "/comms/ground-stations/" + encodeURIComponent(id),
      context,
    ),
    provider: text(data.provider),
    region: text(data.region),
  };
}
export function readDirectory(value: unknown, context: ReadContext): Collection<GroundStationRow> {
  return collection(value, context, "ground-stations", readRow);
}
export function readDetail(value: unknown, context: ReadContext): Detail<GroundStationDetails> {
  const input = record(value),
    data = record(input.data),
    id = identifier(data.id);
  const listHref = missionPath(context) + "/comms/ground-stations",
    detailHref = listHref + "/" + encodeURIComponent(id);
  return {
    navigation: navigation(input.navigation, context, detailHref),
    data: {
      id,
      display_name: text(data.display_name),
      href: exactHref(data.href, detailHref, context),
      list_href: exactHref(data.list_href, listHref, context),
      lifecycle_state: text(data.lifecycle_state),
      provider: text(data.provider),
      region: text(data.region),
      edit_href: exactHref(data.edit_href, detailHref + "/edit", context),
    },
  };
}
