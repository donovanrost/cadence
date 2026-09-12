import type { ReadContext } from "../../shared/read-contracts.ts";
import type { Finding, FindingGroup } from "./read-contracts.ts";
import {
  boolean,
  choice,
  href,
  identifier,
  integer,
  invalid,
  missionPath,
  navigation,
  record,
  text,
} from "../../shared/read-validation.ts";
function readFinding(value: unknown, context: ReadContext): Finding {
  const item = record(value),
    severity = choice(item.severity, ["Blocking", "Warning"]);
  const actionHref = item.action_href == null ? null : href(item.action_href, context);
  const actionLabel = item.action_label == null ? null : text(item.action_label);
  if ((actionHref === null) !== (actionLabel === null)) return invalid();
  return {
    id: item.id === null ? null : identifier(item.id),
    title: text(item.title),
    body: text(item.body, true),
    action_href: actionHref,
    action_label: actionLabel,
    status: { tone: severity === "Blocking" ? "blocked" : "attention", label: severity },
  };
}
export function readValidation(value: unknown, context: ReadContext) {
  const input = record(value),
    data = record(input.data);
  const nav = navigation(input.navigation, context, missionPath(context) + "/comms/validation");
  const count = integer(data.finding_count, 0, 20),
    empty = boolean(data.empty);
  const status = choice(data.status, ["ready", "attention"]);
  if (
    empty !== (count === 0) ||
    (status === "ready") !== empty ||
    !Array.isArray(data.findings) ||
    data.findings.length !== count ||
    !Array.isArray(data.finding_groups) ||
    data.finding_groups.length > 20
  )
    return invalid();
  data.findings.forEach((item) => readFinding(item, context));
  const groups: FindingGroup[] = data.finding_groups.map((value) => {
    const group = record(value);
    if (!Array.isArray(group.findings) || group.findings.length === 0 || group.findings.length > 20)
      return invalid();
    return {
      id: identifier(group.id),
      title: text(group.title),
      description: text(group.description, true),
      findings: group.findings.map((item) => readFinding(item, context)),
    };
  });
  if (
    new Set(groups.map((group) => group.id)).size !== groups.length ||
    groups.reduce((sum, group) => sum + group.findings.length, 0) !== count
  )
    return invalid();
  for (const group of groups) {
    const ids = group.findings.map((item, index) => item.id ?? "finding-" + (index + 1));
    if (new Set(ids).size !== ids.length) return invalid();
  }
  return {
    validation: {
      id: "comms-validation-page",
      title: text(data.title),
      subtitle: "Checks on saved communications setup; not a runtime readiness guarantee.",
      breadcrumbs: nav.breadcrumbs,
      finding_count_suffix: count + (count === 1 ? " finding" : " findings"),
      status: { tone: status, label: empty ? "No findings" : "Needs review" },
      empty,
      empty_state: {
        id: "comms-validation-empty",
        title: "All clear",
        description: "The saved configuration looks consistent.",
      },
      findings_id: "comms-validation-findings",
      finding_groups: groups,
    },
  };
}
