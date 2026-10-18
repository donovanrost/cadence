import type { ReadContext } from "../../shared/read-contracts.ts";
import { isCommsOverviewPresentation } from "./validation.ts";
import { href, invalid, missionPath, navigation, record } from "../../shared/read-validation.ts";
export function readOverview(value: unknown, context: ReadContext) {
  const input = record(value),
    data = input.data;
  navigation(input.navigation, context, missionPath(context) + "/comms");
  if (!isCommsOverviewPresentation(data)) return invalid();
  const overview = data.overview;
  for (const path of [
    overview.transport.manage_href,
    overview.transport.add_href,
    overview.transport.empty_state.action_href,
    ...overview.transport.rows.map((row) => row.href),
    ...overview.validation.finding_groups.flatMap((group) =>
      group.findings.flatMap((finding) => (finding.action_href ? [finding.action_href] : [])),
    ),
  ])
    href(path, context);
  return { presentation: data };
}
