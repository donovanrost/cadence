import { identity, pathIdentity } from "../../shared/legacy-destination";
import { directorySorts } from "./contracts";
import { directoryHref } from "./href";

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function text(value: unknown): value is string {
  return (
    typeof value === "string" &&
    new TextEncoder().encode(value).length <= 512 &&
    // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
    !/[\u0000-\u001f\u007f\ud800-\udfff]/u.test(value)
  );
}

const flag = (value: unknown): value is boolean => typeof value === "boolean";

export function directoryDestination(model: unknown, organization: unknown, mission: unknown) {
  if (
    !identity(organization) ||
    !pathIdentity(mission) ||
    !record(model) ||
    model.version !== 2 ||
    !record(model.context) ||
    model.context.organization_id !== organization ||
    model.context.mission_id !== mission ||
    !record(model.filters)
  )
    return null;

  const { query, tags, starred, archived, sort, page } = model.filters;
  const chosenSort = directorySorts.find((option) => option === sort);
  if (
    !text(query) ||
    !Array.isArray(tags) ||
    tags.length > 10 ||
    !tags.every(text) ||
    !flag(starred) ||
    !flag(archived) ||
    chosenSort === undefined ||
    typeof page !== "number" ||
    !Number.isSafeInteger(page) ||
    page < 1 ||
    page > 1_000_000
  )
    return null;

  return directoryHref(mission, { query, tags, starred, archived, sort: chosenSort }, page);
}
