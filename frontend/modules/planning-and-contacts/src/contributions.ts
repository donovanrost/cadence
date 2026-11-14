import {
  contactScheduleContribution,
  contactRecordContribution,
  reservationContribution,
} from "./features/contact-scheduling/contact.contributions";
import { planReviewContribution } from "./features/contact-plans/plan-review.contribution";
import { fleetDirectoryContribution } from "./features/fleet-planning/directory.contribution";
import {
  fleetStartContribution,
  fleetRunContribution,
} from "./features/fleet-planning/workflow.contributions";
export const planningContributions = [
  contactScheduleContribution,
  contactRecordContribution,
  reservationContribution,
  planReviewContribution,
  fleetDirectoryContribution,
  fleetStartContribution,
  fleetRunContribution,
] as const;
