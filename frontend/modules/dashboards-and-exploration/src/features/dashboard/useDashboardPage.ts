import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from "vue";
import type { GuardedOpsPagePort, OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { WorkspaceSnapshot } from "../workspace/contracts";
import type {
  ActionOutcome,
  DashboardPageData,
  StageAction,
  StageInputs,
  WidgetFields,
} from "./contracts";
import { readActionOutcome, readObservableChoices, record } from "./validation";
import { selectionParams, withParams, type TimeSelection } from "./time-range";

export type DashboardPageProps = {
  page: DashboardPageData;
  context: OpsPageContext;
  port: GuardedOpsPagePort;
  refresh: () => Promise<void>;
};
export type Notice = { tone: "info" | "success" | "warning" | "error"; text: string };

const invalidMessages: Record<string, string> = {
  invalid_input: "Check the field values and observable IDs.",
  invalid_defaults: "Check runtime defaults: use a bounded JSON object with supported contexts.",
  invalid_title: "Enter a widget title of 1–120 characters.",
  invalid_options: "Check the widget's display options and numeric ranges.",
  invalid_binding: "The selected observables do not support this source or scope.",
  invalid_widget: "Check the observable count and source for this widget type.",
  invalid_document: "This dashboard is not ready to publish. Review readiness in Versions.",
  missing_section: "That section no longer exists.",
  missing_placement: "That widget no longer exists.",
  unsupported_widget: "Edit this widget in its owning library.",
  invalid_type: "Choose a supported widget type.",
  capacity: "The dashboard has reached its section or widget limit.",
  unsaved_changes: "Save or discard your changes before publishing.",
};

function outcomeNotice(outcome: ActionOutcome): Notice | null {
  switch (outcome.status) {
    case "ok":
      return null;
    case "invalid":
      return {
        tone: "warning",
        text: invalidMessages[outcome.code] ?? "The change was not accepted.",
      };
    case "conflict":
      return {
        tone: "error",
        text: "Someone else saved this dashboard. Discard to load their version, then edit again.",
      };
    case "rejected":
    case "unknown":
      return {
        tone: "error",
        text: "The change could not be confirmed. Reload the page before trying again.",
      };
  }
}

/** Owns the adopted page, live pause, staged-edit commands and the unsaved-edit guard. */
export function useDashboardPage(props: DashboardPageProps) {
  const page = shallowRef(props.page);
  const pending = ref(false);
  const notice = ref<Notice | null>(null);
  const paused = ref(false);
  const frozen = shallowRef<WorkspaceSnapshot | null>(null);
  let disposed = false;

  // Live refreshes and action replies both deliver pages; an older edit
  // sequence must never replace a newer confirmed staging state.
  function adopt(next: DashboardPageData) {
    if (disposed) return;
    if (next.mode === "edit" && page.value.mode === "edit" && next.sequence < page.value.sequence)
      return;
    page.value = next;
  }
  watch(() => props.page, adopt);

  const snapshot = computed(() =>
    paused.value && frozen.value ? frozen.value : page.value.snapshot,
  );
  const editing = computed(() => page.value.mode === "edit");
  const dirty = computed(() => page.value.mode === "edit" && page.value.edit.dirty);
  const live = computed(() => page.value.live.active && !paused.value);

  function togglePause() {
    paused.value = !paused.value;
    frozen.value = paused.value ? page.value.snapshot : null;
  }

  const base = computed(
    () =>
      `/missions/${encodeURIComponent(props.context.missionId)}/ops/dashboards/${encodeURIComponent(props.context.resourceId ?? "")}`,
  );
  const search = () => (typeof window === "undefined" ? "" : window.location.search);

  function navigate(href: string) {
    try {
      props.port.navigate(href);
    } catch {
      notice.value = { tone: "error", text: "Navigation is unavailable. Reload the page." };
    }
  }
  const viewHref = (changes: Record<string, string | null> = {}) =>
    `${base.value}${withParams(search(), changes)}`;
  const setTime = (selection: TimeSelection) => navigate(viewHref(selectionParams(selection)));
  const setSpacecraft = (id: string | null) => navigate(viewHref({ spacecraft: id }));
  const enterEdit = () => navigate(`${base.value}/edit${withParams(search(), {})}`);
  const exitEdit = () => navigate(viewHref());

  async function execute(action: string, command: Record<string, unknown>): Promise<boolean> {
    if (disposed || pending.value) return false;
    pending.value = true;
    notice.value = null;
    const sequence = page.value.sequence + 1;
    try {
      const outcome = readActionOutcome(
        await props.port.execute(action, { sequence, command }),
        props.context,
      );
      if (disposed) return false;
      if (outcome.page) adopt(outcome.page);
      notice.value = outcomeNotice(outcome);
      return outcome.status === "ok";
    } catch {
      if (!disposed)
        notice.value = {
          tone: "error",
          text: "The change could not be confirmed. Reload the page before trying again.",
        };
      return false;
    } finally {
      if (!disposed) pending.value = false;
    }
  }

  function observed() {
    const current = page.value;
    if (current.mode !== "edit") return null;
    return {
      expected_version: current.edit.document_version,
      expected_revision: current.edit.revision,
    };
  }

  function stage<A extends StageAction>(action: A, input: StageInputs[A]) {
    const control = observed();
    return control ? execute(action, { ...input, ...control }) : Promise.resolve(false);
  }

  async function save() {
    const control = observed();
    if (!control) return false;
    const saved = await execute("save", control);
    if (saved) notice.value = { tone: "success", text: "Draft saved." };
    return saved;
  }

  async function discard() {
    const control = observed();
    return control ? execute("discard", control) : false;
  }

  /** Saves pending edits, then leaves edit mode. */
  async function done() {
    if (dirty.value && !(await save())) return;
    exitEdit();
  }

  async function publish() {
    const version = page.value.publication.latest_version;
    const published = await execute("publish", { version });
    if (published) notice.value = { tone: "success", text: `Version ${version} is now published.` };
    return published;
  }

  async function searchObservables(query: string, fields: WidgetFields) {
    const current = page.value;
    if (current.mode !== "edit") throw Error("Search requires edit mode");
    const expected = {
      version: current.edit.document_version,
      revision: current.edit.revision,
      query,
    };
    const response = record(
      await props.port.execute("search_observables", {
        query,
        fields: { ...fields },
        expected_version: expected.version,
        expected_revision: expected.revision,
      }),
    );
    if (response.status !== "ok") throw Error("Observable search unavailable");
    return readObservableChoices(response.choices, props.context, expected);
  }

  let releaseGuard: (() => void) | null = null;
  onMounted(() => {
    releaseGuard = props.port.guardNavigation(
      () => !dirty.value || window.confirm("Leave without saving your dashboard changes?"),
    );
  });
  onBeforeUnmount(() => {
    disposed = true;
    releaseGuard?.();
  });

  return {
    page,
    snapshot,
    editing,
    dirty,
    live,
    paused,
    pending,
    notice,
    base,
    togglePause,
    setTime,
    setSpacecraft,
    enterEdit,
    exitEdit,
    navigate,
    stage,
    save,
    discard,
    done,
    publish,
    searchObservables,
  };
}
export type DashboardPageState = ReturnType<typeof useDashboardPage>;
