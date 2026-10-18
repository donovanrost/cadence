import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { ActivityAction, ActivityState } from "./contracts";
import { exact, readActivity } from "./validation";
export function useDashboardActivity(props: {
  state: ActivityState;
  context: OpsPageContext;
  port: OpsPagePort;
}) {
  const state = shallowRef(readActivity(props.state, props.context));
  const pending = ref(false),
    review = ref(state.value.phase === "review"),
    notice = ref("");
  const sequence = ref(state.value.sequence);
  const model = computed(() => state.value.model);
  watch(
    () => props.state,
    (next) => {
      if (pending.value) return;
      const admitted = readActivity(next, props.context);
      if (admitted.sequence < sequence.value) return;
      state.value = admitted;
      sequence.value = admitted.sequence;
      if (admitted.phase === "review") review.value = true;
    },
  );
  let dispose: (() => void) | undefined;
  const beforeUnload = (event: BeforeUnloadEvent) => {
    if (pending.value) {
      event.preventDefault();
      event.returnValue = "";
    }
  };
  onMounted(() => {
    dispose = props.port.guardNavigation?.(() => !pending.value);
    window.addEventListener("beforeunload", beforeUnload);
  });
  onBeforeUnmount(() => {
    dispose?.();
    window.removeEventListener("beforeunload", beforeUnload);
  });
  async function execute(action: ActivityAction) {
    if (pending.value) return;
    const observed = model.value;
    const requested = sequence.value + 1;
    sequence.value = requested;
    pending.value = true;
    review.value = true;
    notice.value = "";
    try {
      const response = exact(
        await props.port.execute(action, { sequence: requested, command: {} }),
        ["status", "code", "state"],
      );
      const next = readActivity(response.state, props.context);
      sequence.value = next.sequence;
      if (next.sequence !== requested) throw Error("Unconfirmed sequence");
      if (
        Object.keys(observed.query).some(
          (key) =>
            next.model.query[key as keyof typeof observed.query] !==
            observed.query[key as keyof typeof observed.query],
        )
      )
        throw Error("Changed selection");
      if (response.status !== "ok" || response.code !== null || next.phase !== "ready")
        throw Error("Unconfirmed outcome");
      state.value = next;
      review.value = false;
      notice.value = "History reloaded.";
    } catch {
      notice.value = "History could not be reloaded. Try again.";
    } finally {
      pending.value = false;
    }
  }
  const base = computed(
    () =>
      `/missions/${encodeURIComponent(model.value.mission_id)}/ops/dashboards/${encodeURIComponent(model.value.dashboard_id)}`,
  );
  function href(
    patch: Partial<Record<"version" | "before_version" | "before_event", string | number | null>>,
  ) {
    const q = model.value.query;
    const values = {
      version: q.version,
      before_version: q.before_version,
      before_event: q.before_event,
      selected_publish_issue: q.issue_id,
      ...patch,
    };
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries(values))
      if (value !== null) query.set(key, String(value));
    return `${base.value}/activity${query.size ? `?${query}` : ""}`;
  }
  function navigate(event: MouseEvent, path: string) {
    if (pending.value) {
      event.preventDefault();
      return;
    }
    if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey)
      return;
    event.preventDefault();
    props.port.navigate(path);
  }
  return { model, pending, review, notice, execute, base, href, navigate };
}
