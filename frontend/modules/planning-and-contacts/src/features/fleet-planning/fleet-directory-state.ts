import { onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { FleetDirectoryPort } from "./OpsFleetPlanning.contracts";
import { admitFleetDirectory } from "./fleet-directory";
export function useFleetDirectory(input: () => unknown, port?: FleetDirectoryPort) {
  const directory = shallowRef(admitFleetDirectory(input(), port?.context));
  const pending = ref(false),
    notice = ref("");
  let context = port?.context ?? directory.value?.context;
  let query = directory.value?.query,
    generation = 0,
    active = true;
  function replace(value: unknown) {
    const next = admitFleetDirectory(value, context);
    if (!next || (query && (next.query.page !== query.page || next.query.state !== query.state)))
      return false;
    context ??= next.context;
    query ??= next.query;
    directory.value = next;
    return true;
  }
  watch(input, (value) => {
    generation++;
    pending.value = false;
    notice.value = "";
    if (!replace(value)) directory.value = null;
  });
  onBeforeUnmount(() => {
    active = false;
    generation++;
  });
  async function refresh() {
    if (!port || pending.value) return;
    const run = ++generation;
    pending.value = true;
    try {
      const result = await port.refresh();
      if (!active || generation !== run) return;
      notice.value = replace(result)
        ? "Fleet directory refreshed."
        : "Updated fleet evidence is unavailable. The previous directory is retained.";
    } catch {
      if (active && generation === run)
        notice.value = "Fleet evidence could not be refreshed. The previous directory is retained.";
    } finally {
      if (active && generation === run) pending.value = false;
    }
  }
  return { directory, pending, notice, refresh, connected: !!port };
}
