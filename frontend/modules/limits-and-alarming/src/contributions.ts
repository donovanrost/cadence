import { alarmConditionsContribution } from "./features/alarm-conditions/contribution";
import { definitionsContribution } from "./features/definitions/contribution";
import { postureContribution } from "./features/posture/contribution";
export const contributions = [
  definitionsContribution,
  postureContribution,
  alarmConditionsContribution,
] as const;
