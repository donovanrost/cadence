import { opsPages } from "./ops-workspace/features/module-pages/contributions";

// Existing admission/interaction suites start with downloaded code. Loading and stale imports
// have separate lifecycle tests, and the production browser journey exercises cold navigation.
async function ready<T>(registry: { ids: readonly string[]; load(id: string): Promise<T> }) {
  return Object.fromEntries(
    await Promise.all(registry.ids.map(async (id) => [id, await registry.load(id)] as const)),
  );
}
export const loadedOpsPages = await ready(opsPages);
