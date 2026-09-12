import { computed, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { LibraryAction, LibraryQuery, LibraryReceipt, LibraryState } from "./contracts";
import { exact, readLibrary, readReceipt } from "./validation";
import { parseWidgetJson, widgetExample } from "./widget-json";
export function useDashboardLibrary(props: {
  state: LibraryState;
  context: OpsPageContext;
  port: OpsPagePort;
}) {
  const state = shallowRef(readLibrary(props.state, props.context));
  const model = computed(() => state.value.model),
    pending = ref(false),
    review = ref(state.value.phase === "review"),
    sequence = ref(state.value.sequence),
    notice = ref(""),
    jsonError = ref("");
  const mode = ref<"create_item" | "add_version">(
    model.value.selected ? "add_version" : "create_item",
  );
  const draft = reactive({
    name: "",
    description: "",
    change_summary: "",
    widget_json: model.value.selected?.widget_json ?? widgetExample,
  });
  const clean = ref(JSON.stringify(draft));
  const dirty = computed(() => JSON.stringify(draft) !== clean.value);
  const receipt = shallowRef<LibraryReceipt | null>(null);
  const query = ref(model.value.query.q),
    dashboardQuery = ref(model.value.query.dashboard_query);
  const disabled = computed(() => pending.value || review.value);
  watch(
    () => props.state,
    (value) => {
      if (pending.value) return;
      const next = readLibrary(value, props.context);
      if (next.sequence < sequence.value) return;
      if (
        dirty.value &&
        mode.value === "add_version" &&
        next.model.selected?.item.latest_version !== model.value.selected?.item.latest_version
      ) {
        review.value = true;
        notice.value =
          "The library changed while you were editing. Reload and review the saved versions before saving your retained definition.";
      }
      state.value = next;
      sequence.value = next.sequence;
      if (next.phase === "review") review.value = true;
    },
  );
  let dispose: (() => void) | undefined;
  function canLeave() {
    return (
      !pending.value &&
      (!dirty.value ||
        window.confirm("Leave the library and discard the unsaved widget definition?"))
    );
  }
  function unload(e: BeforeUnloadEvent) {
    if (pending.value || dirty.value) {
      e.preventDefault();
      e.returnValue = "";
    }
  }
  onMounted(() => {
    dispose = props.port.guardNavigation?.(canLeave);
    window.addEventListener("beforeunload", unload);
  });
  onBeforeUnmount(() => {
    dispose?.();
    window.removeEventListener("beforeunload", unload);
  });
  function changeMode(next: "create_item" | "add_version") {
    if (
      disabled.value ||
      (next === "add_version" && !model.value.selected) ||
      (dirty.value && !window.confirm("Discard the unsaved widget definition?"))
    )
      return;
    mode.value = next;
    Object.assign(draft, {
      name: "",
      description: "",
      change_summary: "",
      widget_json: next === "add_version" ? model.value.selected!.widget_json : widgetExample,
    });
    clean.value = JSON.stringify(draft);
    jsonError.value = "";
  }
  function command(action: LibraryAction): Record<string, unknown> {
    const selected = model.value.selected,
      target = model.value.target;
    if (action === "reload_library") return {};
    if (action === "add_to_draft") {
      if (!selected || !target) throw Error("Select a library version and target dashboard first.");
      return {
        item_id: selected.item.id,
        version: selected.version,
        dashboard_id: target.id,
        expected_version: target.version,
      };
    }
    parseWidgetJson(draft.widget_json);
    if (action === "create_item") return { ...draft };
    if (!selected) throw Error("Select a reusable widget first.");
    return {
      item_id: selected.item.id,
      expected_version: selected.item.latest_version,
      widget_json: draft.widget_json,
      change_summary: draft.change_summary,
    };
  }
  function matches(result: LibraryReceipt, action: LibraryAction, input: Record<string, unknown>) {
    if (result.event !== action) return false;
    if (action === "create_item") return result.library_version === 1;
    if (result.item_id !== input.item_id) return false;
    if (action === "add_version")
      return result.library_version === (input.expected_version as number) + 1;
    return (
      result.library_version === input.version &&
      result.dashboard_id === input.dashboard_id &&
      result.document_version === (input.expected_version as number) + 1
    );
  }
  async function execute(action: LibraryAction) {
    if (pending.value || (review.value && action !== "reload_library")) return;
    let input: Record<string, unknown>;
    try {
      input = command(action);
    } catch (error) {
      jsonError.value = error instanceof Error ? error.message : "Check the widget definition.";
      return;
    }
    if (
      action === "add_to_draft" &&
      !window.confirm(
        `Add library v${input.version} to ${model.value.target!.name} as a new draft after v${input.expected_version}? Publication stays unchanged.`,
      )
    )
      return;
    const requested = ++sequence.value,
      observedQuery = model.value.query;
    pending.value = true;
    review.value = true;
    notice.value = "";
    jsonError.value = "";
    receipt.value = null;
    try {
      const response = exact(
        await props.port.execute(action, { sequence: requested, command: input }),
        ["status", "code", "receipt", "state"],
      );
      const next = readLibrary(response.state, props.context);
      sequence.value = next.sequence;
      if (
        next.sequence !== requested ||
        Object.keys(observedQuery).some(
          (k) =>
            next.model.query[k as keyof LibraryQuery] !== observedQuery[k as keyof LibraryQuery],
        )
      )
        throw Error("Unconfirmed sequence or selection");
      if (
        response.status === "invalid" &&
        ["invalid_input", "invalid_widget", "capacity"].includes(response.code as string) &&
        response.receipt === null &&
        next.phase === "ready"
      ) {
        state.value = next;
        review.value = false;
        notice.value =
          "The change was not saved. Check the name, widget definition and dashboard capacity. Your draft is retained.";
        return;
      }
      if (response.status !== "ok" || response.code !== null || next.phase !== "ready")
        throw Error("Unconfirmed change");
      if (action === "reload_library") {
        if (response.receipt !== null) throw Error("Unexpected receipt");
      } else {
        const result = readReceipt(response.receipt);
        if (!matches(result, action, input)) throw Error("Unconfirmed receipt");
        receipt.value = result;
      }
      state.value = next;
      review.value = false;
      if (action === "create_item" || action === "add_version") {
        clean.value = JSON.stringify(draft);
      }
      notice.value =
        action === "reload_library"
          ? "Library reloaded. Review saved versions and consumers before another change."
          : action === "add_to_draft"
            ? "Pinned widget added to a new dashboard draft. Publication is unchanged."
            : "Immutable library version saved. Existing consumers keep their pinned versions.";
    } catch {
      notice.value =
        "The outcome could not be confirmed. Reload the library and review saved versions and consumers before trying again.";
    } finally {
      pending.value = false;
    }
  }
  const base = computed(
    () => `/missions/${encodeURIComponent(model.value.mission_id)}/ops/dashboards`,
  );
  function href(patch: Partial<LibraryQuery> = {}) {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries({ ...model.value.query, ...patch }))
      if (value !== null && value !== "") params.set(key, String(value));
    return `${base.value}/library${params.size ? `?${params}` : ""}`;
  }
  function navigate(event: MouseEvent, path: string) {
    if (pending.value) {
      event.preventDefault();
      return;
    }
    if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey)
      return;
    event.preventDefault();
    if (props.port.guardNavigation || canLeave()) props.port.navigate(path);
  }
  function go(patch: Partial<LibraryQuery>) {
    if (!pending.value && (props.port.guardNavigation || canLeave()))
      props.port.navigate(href(patch));
  }
  function selectTarget(event: Event) {
    const select = event.target as HTMLSelectElement;
    const target = select.value;
    // Keep the displayed selection on its admitted identity until navigation succeeds.
    select.value = model.value.target?.id || "";
    go({ target_id: target || null });
  }
  return {
    model,
    pending,
    review,
    notice,
    jsonError,
    mode,
    draft,
    dirty,
    disabled,
    receipt,
    query,
    dashboardQuery,
    changeMode,
    execute,
    base,
    href,
    navigate,
    go,
    selectTarget,
  };
}
