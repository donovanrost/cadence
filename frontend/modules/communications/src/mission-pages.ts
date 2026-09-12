import { missionPages as feature0 } from "./features/overview/mission.contribution";
import { missionPages as feature1 } from "./features/setup-validation/mission.contribution";
import { missionPages as feature2 } from "./features/transports/mission.contribution";
import { missionPages as feature3 } from "./features/routing/mission.contribution";
import { missionPages as feature4 } from "./features/ground-stations/mission.contribution";
import { setupPages as transportSetup } from "./features/transports/setup.contribution";
import { setupPages as routingSetup } from "./features/routing/setup.contribution";
import { setupPages as stationSetup } from "./features/ground-stations/setup.contribution";
import { missionPages as providers } from "./features/providers/mission.contribution";

export const communicationsMissionPages = [
  ...feature0,
  ...feature1,
  ...feature2,
  ...feature3,
  ...feature4,
  ...transportSetup,
  ...routingSetup,
  ...stationSetup,
  ...providers,
] as const;
