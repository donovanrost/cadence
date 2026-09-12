import { opsPages } from "./ops-workspace/features/module-pages/contributions";
import { missionModulePages } from "./mission-and-spacecraft/features/module-pages/mission-contributions";
import { spacecraftModulePages } from "./mission-and-spacecraft/features/module-pages/contributions";
import { organizationModulePages } from "./administration/features/module-pages/contributions";

// Existing admission/interaction suites start with downloaded code. Loading and stale imports
// have separate lifecycle tests, and the production browser journey exercises cold navigation.
async function ready<T>(registry: { ids: readonly string[]; load(id: string): Promise<T> }) {
  return Object.fromEntries(
    await Promise.all(registry.ids.map(async (id) => [id, await registry.load(id)] as const)),
  );
}
export const [loadedOpsPages, loadedMissionPages, loadedSpacecraftPages, loadedOrganizationPages] =
  await Promise.all([
    ready(opsPages),
    ready(missionModulePages),
    ready(spacecraftModulePages),
    ready(organizationModulePages),
  ]);
