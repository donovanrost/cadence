import {
  contactScheduleContribution,
  contactRecordContribution,
  reservationContribution,
} from "./features/contact-scheduling/contact.contributions";
import { requirementTemplateContribution } from "./features/contact-requirements/template.contribution";
import { planReviewContribution } from "./features/contact-plans/plan-review.contribution";
import { requirementDeclarationContribution } from "./features/contact-requirements/declaration.contribution";
import {
  requirementDirectoryContribution,
  requirementReviewContribution,
} from "./features/contact-requirements/requirement.contributions";
import { fleetPolicyContribution } from "./features/fleet-planning/policy.contribution";
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
  requirementTemplateContribution,
  requirementDeclarationContribution,
  requirementDirectoryContribution,
  requirementReviewContribution,
  fleetPolicyContribution,
  fleetDirectoryContribution,
  fleetStartContribution,
  fleetRunContribution,
] as const;
