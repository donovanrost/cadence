import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  shallowRef,
  watch,
} from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { Choice, DirectoryState, Receipt } from "./contracts";
import { exact, readDirectory, readReceipt, readSearch, readState } from "./validation";
export function usePlaylistAuthoring(props: {
  state: DirectoryState;
  context: OpsPageContext;
  port: OpsPagePort;
}) {
  const state = shallowRef(readState(props.state, props.context)),
    model = computed(() => state.value.model);
  const draft = reactive({ name: "", description: "", dwell_seconds: 30, wallboard_mode: false });
  const queue = ref<(Pick<Choice, "id" | "name"> & { key: number })[]>([]),
    choices = shallowRef(model.value.choices);
  const signature = () => JSON.stringify([draft, queue.value]);
  const clean = ref(signature());
  const dirty = computed(() => signature() !== clean.value),
    pending = ref(false),
    review = ref(state.value.phase === "review"),
    notice = ref(""),
    receipt = ref<Receipt | null>(null);
  const searchText = ref(""),
    appliedSearch = ref(""),
    searching = ref(false),
    searchError = ref(""),
    collectionQuery = ref(model.value.query.q);
  let lookup = 0,
    entryKey = 0,
    sequence = state.value.sequence,
    dispose: (() => void) | undefined;
  const disabled = computed(() => pending.value || review.value);
  watch(
    () => props.state,
    (value) => {
      if (pending.value) return;
      const next = readState(value, props.context);
      if (next.sequence < sequence) return;
      state.value = next;
      sequence = next.sequence;
      if (next.phase === "review") review.value = true;
    },
  );
  function canLeave() {
    return !pending.value && (!dirty.value || window.confirm("Leave this unsaved playlist?"));
  }
  const unload = (e: BeforeUnloadEvent) => {
    if (dirty.value || pending.value) {
      e.preventDefault();
      e.returnValue = "";
    }
  };
  onMounted(() => {
    dispose = props.port.guardNavigation?.(canLeave);
    window.addEventListener("beforeunload", unload);
  });
  onBeforeUnmount(() => {
    lookup++;
    dispose?.();
    window.removeEventListener("beforeunload", unload);
  });
  function add(choice: Choice) {
    if (!disabled.value && queue.value.length < 100)
      queue.value.push({ id: choice.id, name: choice.name, key: ++entryKey });
  }
  function remove(index: number) {
    if (!disabled.value) queue.value.splice(index, 1);
  }
  function move(index: number, delta: number, event?: MouseEvent) {
    const target = index + delta;
    if (disabled.value || target < 0 || target >= queue.value.length) return;
    const control = event?.currentTarget as HTMLButtonElement | undefined;
    const restoreFocus = control && document.activeElement === control;
    const [entry] = queue.value.splice(index, 1);
    if (!entry) return;
    queue.value.splice(target, 0, entry);
    if (restoreFocus)
      void nextTick(() => {
        if (control.disabled) control.closest("li")?.focus();
        else control.focus();
      });
  }
  async function search(after: string | null = null) {
    const request = ++lookup,
      q = after ? appliedSearch.value : searchText.value.trim();
    searching.value = true;
    searchError.value = "";
    try {
      const result = exact(
        await props.port.execute("search_dashboards", { q, ...(after ? { after } : {}) }),
        ["status", "data"],
      );
      if (result.status !== "ok") throw Error();
      const data = readSearch(result.data, props.context);
      if (data.query.q !== q || data.query.after !== after) throw Error();
      if (request === lookup) {
        choices.value = data.choices;
        appliedSearch.value = q;
      }
    } catch {
      if (request === lookup)
        searchError.value = "Dashboard search is unavailable. The selected queue is retained.";
    } finally {
      if (request === lookup) searching.value = false;
    }
  }
  async function execute(event: "create_playlist" | "reload_playlists") {
    if (pending.value || (review.value && event !== "reload_playlists")) return;
    const fields =
      event === "create_playlist" ? { ...draft, dashboard_ids: queue.value.map((r) => r.id) } : {};
    if (
      event === "create_playlist" &&
      (!draft.name.trim() ||
        !queue.value.length ||
        !Number.isInteger(draft.dwell_seconds) ||
        draft.dwell_seconds < 5 ||
        draft.dwell_seconds > 900)
    ) {
      notice.value =
        "Add a name, at least one dashboard, and a dwell time between 5 and 900 seconds.";
      return;
    }
    const requested = ++sequence;
    pending.value = true;
    review.value = true;
    receipt.value = null;
    notice.value = "";
    try {
      const r = exact(await props.port.execute(event, { sequence: requested, fields }), [
        "status",
        "receipt",
        "sequence",
        "phase",
        "model",
      ]);
      const next = readDirectory(r.model, props.context);
      if (!Number.isInteger(r.sequence)) throw Error();
      sequence = r.sequence as number;
      if (
        sequence !== requested ||
        next.query.q !== model.value.query.q ||
        next.query.after !== model.value.query.after
      )
        throw Error();
      if (r.status === "invalid" && r.phase === "ready" && r.receipt === null) {
        review.value = false;
        notice.value =
          "Playlist was not saved. Check its name and active dashboard references; your queue is retained.";
        return;
      }
      if (r.status !== "ok") throw Error();
      if (event === "create_playlist") {
        const saved = readReceipt(r.receipt);
        if (
          r.phase !== "review" ||
          saved.count !== queue.value.length ||
          saved.name !== draft.name.trim()
        )
          throw Error();
        receipt.value = saved;
        clean.value = signature();
        notice.value = "Playlist created. Reload before starting another playlist.";
      } else {
        if (r.phase !== "ready" || r.receipt !== null) throw Error();
        review.value = false;
        notice.value = "Playlists reloaded. Review the saved list before another creation.";
      }
      state.value = { model: next, sequence, phase: r.phase as DirectoryState["phase"] };
    } catch {
      notice.value =
        "The outcome could not be confirmed. Reload and check saved playlists before trying again.";
    } finally {
      pending.value = false;
    }
  }
  const base = computed(
    () => `/missions/${encodeURIComponent(model.value.mission_id)}/ops/dashboards`,
  );
  function href(q = collectionQuery.value, after: string | null = null) {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    if (after) params.set("after", after);
    return `${base.value}/playlists${params.size ? `?${params}` : ""}`;
  }
  function go(path: string) {
    if (!pending.value && (props.port.guardNavigation || canLeave())) props.port.navigate(path);
  }
  function navigate(e: MouseEvent, path: string) {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    go(path);
  }
  return {
    model,
    draft,
    queue,
    choices,
    dirty,
    pending,
    review,
    notice,
    receipt,
    disabled,
    searchText,
    searching,
    searchError,
    collectionQuery,
    add,
    remove,
    move,
    search,
    execute,
    base,
    href,
    go,
    navigate,
  };
}
