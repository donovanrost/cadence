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
import {
  readActionOutcome,
  readComparison,
  readObservableChoices,
  readVersionList,
  record,
} from "./validation";
import { selectionParams, withParams, type TimeSelection } from "./time-range";

export type DashboardPageProps = {
  page: DashboardPageData;
  context: OpsPageContext;
  port: GuardedOpsPagePort;
  refresh: () => Promise<void>;
};
export type Notice = { tone: "info" | "success" | "warning" | "error"; text: string };
export type SaveOptions = { message?: string; defaults?: { time?: boolean; scope?: boolean } };

const invalidMessages: Record<string, string> = {
  invalid_input: "Check the field values and observable IDs.",
  invalid_defaults: "Check runtime defaults: use a bounded JSON object with supported contexts.",
  invalid_title: "Enter a widget title of 1–120 characters.",
  invalid_options: "Check the widget's display options and numeric ranges.",
  invalid_binding: "The selected observables do not support this source or scope.",
  invalid_widget: "Check the observable count and source for this widget type.",
  invalid_document:
    "This dashboard can't be saved yet: a widget's bindings or sources are not valid.",
  missing_section: "That section no longer exists.",
  missing_placement: "That widget no longer exists.",
  unsupported_widget: "Edit this widget in its owning library.",
  invalid_type: "Choose a supported widget type.",
  capacity: "The dashboard has reached its section or widget limit.",
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
        text: "Someone else saved this dashboard while you were editing.",
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

  /** Sequenced effects: the server confirms each against the page's last sequence. */
  async function execute(
    action: string,
    command: Record<string, unknown>,
  ): Promise<ActionOutcome | null> {
    if (disposed || pending.value) return null;
    pending.value = true;
    notice.value = null;
    const sequence = page.value.sequence + 1;
    try {
      const outcome = readActionOutcome(
        await props.port.execute(action, { sequence, command }),
        props.context,
      );
      if (disposed) return null;
      if (outcome.page) adopt(outcome.page);
      notice.value = outcomeNotice(outcome);
      return outcome;
    } catch {
      if (!disposed)
        notice.value = {
          tone: "error",
          text: "The change could not be confirmed. Reload the page before trying again.",
        };
      return null;
    } finally {
      if (!disposed) pending.value = false;
    }
  }
  const succeeded = (outcome: ActionOutcome | null) => outcome?.status === "ok";

  /** Read-only queries (versions, comparisons): no sequence, no page change. */
  async function query(action: string, input: Record<string, unknown>) {
    const response = record(await props.port.execute(action, input));
    if (response.status !== "ok") throw Error(`${action} unavailable`);
    return response;
  }

  function observed() {
    const current = page.value;
    if (current.mode !== "edit") return null;
    return {
      expected_version: current.edit.document_version,
      expected_revision: current.edit.revision,
    };
  }

  async function stage<A extends StageAction>(action: A, input: StageInputs[A]) {
    const control = observed();
    return control ? succeeded(await execute(action, { ...input, ...control })) : false;
  }

  /** Saves a new current version; like Grafana, the author stays in edit mode. */
  async function save(options: SaveOptions = {}) {
    const control = observed();
    if (!control) return false;
    const saved = succeeded(
      await execute("save", {
        ...control,
        ...(options.message ? { message: options.message } : {}),
        ...(options.defaults ? { defaults: options.defaults } : {}),
      }),
    );
    if (saved)
      notice.value = { tone: "success", text: `Saved version ${page.value.saved.version}.` };
    return saved;
  }

  async function saveAsCopy(name: string) {
    const outcome = await execute("save_as_copy", { name });
    const id = outcome?.status === "ok" ? outcome.result?.dashboard_id : undefined;
    if (!id) return false;
    // The copy is a new dashboard; leaving discards nothing because this draft is unchanged.
    navigate(`${base.value.replace(/\/[^/]+$/, "")}/${encodeURIComponent(id)}`);
    return true;
  }

  async function discard() {
    const control = observed();
    return control ? succeeded(await execute("discard", control)) : false;
  }

  /** Leaves edit mode; unsaved changes are discarded first so the leave guard stays quiet. */
  async function discardAndExit() {
    if (dirty.value && !(await discard())) return;
    exitEdit();
  }

  /** After someone else saved: replay my edits onto their version. */
  async function rebase() {
    const outcome = await execute("rebase", {});
    if (outcome?.status !== "ok") return false;
    const skipped = outcome.result?.skipped ?? [];
    notice.value = skipped.length
      ? {
          tone: "warning",
          text: `Your edits were reapplied on the latest version, except ${skipped.length} that no longer apply (${skipped.map((e) => e.replaceAll("_", " ")).join(", ")}).`,
        }
      : { tone: "info", text: "Your edits were reapplied on the latest version." };
    return true;
  }

  async function restore(version: number) {
    const restored = succeeded(
      await execute("restore", { version, expected_version: page.value.saved.version }),
    );
    if (restored)
      notice.value = {
        tone: "success",
        text: `Restored version ${version} as version ${page.value.saved.version}.`,
      };
    return restored;
  }

  const versions = async () =>
    readVersionList((await query("versions", {})).versions, props.context);
  const compare = async (from: number, to: number) =>
    readComparison((await query("compare", { from, to })).comparison);
  const compareStaged = async () => readComparison((await query("compare_staged", {})).comparison);

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
    saveAsCopy,
    discard,
    discardAndExit,
    rebase,
    restore,
    versions,
    compare,
    compareStaged,
    searchObservables,
  };
}
export type DashboardPageState = ReturnType<typeof useDashboardPage>;
