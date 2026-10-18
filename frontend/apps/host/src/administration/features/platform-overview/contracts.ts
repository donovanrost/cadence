import { observation, record, type Observation } from "../../shared/platform-contract";
export type PlatformOverview = Observation & {
  counts: { organizations: number; active_users: number };
};
export function readPlatformOverview(value: unknown, userId: unknown): PlatformOverview {
  observation(value, userId);
  if (
    !record(value.counts) ||
    !Number.isSafeInteger(value.counts.organizations) ||
    Number(value.counts.organizations) < 0 ||
    !Number.isSafeInteger(value.counts.active_users) ||
    Number(value.counts.active_users) < 0
  )
    throw Error("Invalid platform counts");
  return value as PlatformOverview;
}
