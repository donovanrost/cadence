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
  const writable = computed(
    () => !pending.value && !review.value && model.value.author && !model.value.archived,
  );
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
    if (pending.value || (action !== "reload_activity" && !writable.value)) return;
    const observed = model.value;
    if (
      action !== "reload_activity" &&
      !window.confirm(
        action === "restore_version"
          ? `Restore version ${observed.selected.version} as a new draft after version ${observed.document_version}? The published version will not change.`
          : `Publish version ${observed.selected.version}? This replaces the published pointer; draft version ${observed.document_version} is retained.`,
      )
    )
      return;
    const requested = sequence.value + 1;
    sequence.value = requested;
    pending.value = true;
    review.value = true;
    notice.value = "";
    try {
      const response = exact(
        await props.port.execute(action, {
          sequence: requested,
          command:
            action === "reload_activity"
              ? {}
              : {
                  version: observed.selected.version,
                  expected_version: observed.document_version,
                  expected_revision: observed.revision,
                },
        }),
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
      if (
        response.status === "invalid" &&
        ["invalid_input", "invalid_document"].includes(response.code as string) &&
        next.phase === "ready"
      ) {
        state.value = next;
        review.value = false;
        notice.value =
          "The selected version could not pass validation or publication readiness. No change was applied.";
        return;
      }
      if (response.status !== "ok" || response.code !== null || next.phase !== "ready")
        throw Error("Unconfirmed outcome");
      if (
        action !== "reload_activity" &&
        (next.model.document_version !==
          observed.document_version + (action === "restore_version" ? 1 : 0) ||
          next.model.revision !== observed.revision + 1 ||
          next.model.published_version !==
            (action === "publish_version" ? observed.selected.version : observed.published_version))
      )
        throw Error("Unconfirmed revision");
      state.value = next;
      review.value = false;
      notice.value =
        action === "restore_version"
          ? "Version restored as a new draft. Publication is unchanged."
          : action === "publish_version"
            ? "Selected version published. The latest draft is retained."
            : "History reloaded. Review the current versions before making changes.";
    } catch {
      notice.value =
        "The outcome could not be confirmed. Reload history and review the current versions before another change.";
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
  return { model, pending, review, writable, notice, execute, base, href, navigate };
}
