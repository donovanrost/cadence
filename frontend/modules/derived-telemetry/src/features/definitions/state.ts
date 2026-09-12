import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import {
  admitDocument,
  admitReceipt,
  id,
  record,
  validInput,
  type Definition,
  type DefinitionInput,
  type DefinitionReceipt,
  type DefinitionsDocument,
  type DefinitionsPort,
} from "./contracts";
const rejectionMessages: Readonly<Record<string, string>> = {
  review_conflict: "This definition changed. Refresh and review its current version before saving.",
  review_required: "Review the current definition before saving.",
  invalid_expression:
    "The expression is invalid. Use a stateless expression with canonical point IDs.",
  required_field: "Point ID and expression are required.",
  invalid_field: "Check the point ID, display name and expression length.",
  forbidden: "You no longer have permission to save definitions. Your draft is retained.",
  application_unavailable:
    "Derived Telemetry is no longer available in this mission. Your draft is retained.",
  unsupported_action: "This definition editor is no longer supported. Refresh before trying again.",
  invalid_input:
    "The definition request was rejected. Refresh and review the retained draft before saving.",
};
const empty = (): DefinitionInput => ({
  point_id: "",
  point_name: "",
  expression: "",
  expected_definition_id: null,
  expected_version: 0,
});
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
const contextKeys = ["organization_id", "mission_id", "actor_id", "installation_id"] as const;
const sameScope = (a: unknown, b: DefinitionsDocument["context"]) =>
  record(a) && contextKeys.every((k) => a[k] === b[k]);
function storage() {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}
export function useDefinitions(initial: () => DefinitionsDocument, port: DefinitionsPort) {
  const first = initial(),
    page = shallowRef(first),
    draft = ref(empty()),
    baseline = ref(empty());
  const pending = shallowRef<{ key: string; input: DefinitionInput } | null>(null),
    confirmed = shallowRef<DefinitionReceipt | null>(null),
    confirmedInput = shallowRef<DefinitionInput | null>(null);
  const working = ref(false),
    reading = ref(false),
    readFailed = ref(false),
    storageError = ref(""),
    notice = ref("");
  const key =
      "cadence.derived-telemetry.definition-draft.v1:" +
      JSON.stringify(contextKeys.map((k) => first.context[k])),
    journal = storage();
  let active = true,
    generation = 0;
  const dirty = computed(() => !same(draft.value, baseline.value));
  const current = computed(() => {
    const s = page.value.selection;
    return s?.available ? s.current : null;
  });
  const stale = computed(() => {
    const d = draft.value;
    const known =
      current.value?.point_id === d.point_id
        ? current.value
        : page.value.definitions.items.find((x) => x.point_id === d.point_id);
    return (
      !!known && (known.version !== d.expected_version || known.id !== d.expected_definition_id)
    );
  });
  const locked = computed(
    () => working.value || !!pending.value || reading.value || !!storageError.value,
  );
  const canSave = computed(
    () => !locked.value && !readFailed.value && !stale.value && validInput(normalized()),
  );
  function normalized(): DefinitionInput {
    return {
      ...draft.value,
      point_id: draft.value.point_id.trim(),
      point_name: draft.value.point_name.trim() || draft.value.point_id.trim(),
      expression: draft.value.expression.trim(),
    };
  }
  function persist() {
    try {
      if (!journal) throw Error();
      journal.setItem(
        key,
        JSON.stringify({
          version: 1,
          context: first.context,
          draft: draft.value,
          baseline: baseline.value,
          pending: pending.value,
          confirmed: confirmed.value
            ? { receipt: confirmed.value, input: confirmedInput.value }
            : null,
        }),
      );
      storageError.value = "";
      return true;
    } catch {
      storageError.value =
        "This tab could not preserve your draft and pending save. Refresh before saving or leaving.";
      return false;
    }
  }
  function draftShape(v: unknown): v is DefinitionInput {
    return (
      record(v) &&
      typeof v.point_id === "string" &&
      typeof v.point_name === "string" &&
      typeof v.expression === "string" &&
      Number.isSafeInteger(v.expected_version) &&
      (v.expected_version as number) >= 0 &&
      (v.expected_definition_id === null || id(v.expected_definition_id)) &&
      JSON.stringify(v).length < 40000
    );
  }
  try {
    const raw = journal?.getItem(key);
    if (raw) {
      if (raw.length > 200000) throw Error();
      const saved: unknown = JSON.parse(raw);
      if (
        !record(saved) ||
        saved.version !== 1 ||
        !sameScope(saved.context, first.context) ||
        !draftShape(saved.draft) ||
        !draftShape(saved.baseline)
      )
        throw Error();
      if (
        saved.pending !== null &&
        (!record(saved.pending) || !id(saved.pending.key) || !validInput(saved.pending.input))
      )
        throw Error();
      draft.value = saved.draft;
      baseline.value = saved.baseline;
      pending.value = saved.pending as typeof pending.value;
      if (saved.confirmed !== null) {
        if (!record(saved.confirmed) || !validInput(saved.confirmed.input)) throw Error();
        confirmed.value = admitReceipt(saved.confirmed.receipt, saved.confirmed.input);
        if (!confirmed.value) throw Error();
        confirmedInput.value = saved.confirmed.input;
      }
    }
  } catch {
    storageError.value =
      "This tab's saved work could not be recovered. Review current definitions in a new tab before making another change.";
  }
  watch(
    draft,
    () => {
      if (!working.value) persist();
    },
    { deep: true, flush: "sync" },
  );
  function replace(def: Definition | null, expression?: string) {
    if (pending.value || working.value) return;
    if (dirty.value && !window.confirm("Replace this unsaved definition draft?")) return;
    const next = def
      ? {
          point_id: def.point_id,
          point_name: def.point_name,
          expression: def.expression,
          expected_definition_id: def.id,
          expected_version: def.version,
        }
      : empty();
    baseline.value = { ...next };
    draft.value = { ...next, ...(expression === undefined ? {} : { expression }) };
    notice.value = def
      ? `Reviewing ${def.point_id} version ${def.version}.`
      : "New definition draft.";
    persist();
  }
  function accept(value: unknown) {
    const next = admitDocument(value);
    if (!next || !sameScope(next.context, first.context)) return false;
    page.value = next;
    readFailed.value = false;
    return true;
  }
  watch(initial, (value) => {
    if (!accept(value)) readFailed.value = true;
  });
  async function refresh() {
    if (working.value) return;
    const n = ++generation;
    reading.value = true;
    try {
      const value = await port.read();
      if (!active || n !== generation) return;
      if (!accept(value)) throw Error();
      notice.value = pending.value
        ? "Current definitions refreshed. Recover the pending response before editing."
        : "Definitions refreshed. Your draft was retained.";
    } catch {
      if (active && n === generation) {
        readFailed.value = true;
        notice.value =
          "Current definitions could not be read. Your draft is retained; refresh before saving.";
      }
    } finally {
      if (active && n === generation) reading.value = false;
    }
  }
  async function send(recovery = true) {
    const intent = pending.value;
    if (!intent || working.value) return;
    working.value = true;
    let completed = false;
    try {
      const result = await port.save(intent.input, intent.key);
      if (!active) return;
      const receipt = admitReceipt(result, intent.input);
      if (!receipt) throw Error();
      confirmed.value = receipt;
      confirmedInput.value = intent.input;
      pending.value = null;
      baseline.value = {
        ...intent.input,
        expected_definition_id: receipt.result.definitionId,
        expected_version: receipt.result.version,
      };
      draft.value = { ...baseline.value };
      completed = true;
      persist();
      notice.value = `Definition version ${receipt.result.version} saved.`;
    } catch (e) {
      if (!active) return;
      const code = record(e) && typeof e.code === "string" ? e.code : "";
      if (
        [
          "review_conflict",
          "review_required",
          "invalid_expression",
          "required_field",
          "invalid_field",
        ].includes(code) ||
        (!recovery &&
          ["forbidden", "application_unavailable", "unsupported_action", "invalid_input"].includes(
            code,
          ))
      ) {
        pending.value = null;
        readFailed.value = true;
        notice.value =
          rejectionMessages[code] ??
          "The definition was rejected. Refresh and review before saving.";
      } else
        notice.value =
          "The save response is unconfirmed. Recover this same save before making another change.";
      persist();
    } finally {
      if (active) working.value = false;
    }
    if (active && completed) await refresh();
  }
  async function save() {
    if (!canSave.value) return;
    pending.value = { key: crypto.randomUUID(), input: normalized() };
    if (!persist()) {
      pending.value = null;
      return;
    }
    await send(false);
  }
  function navigate(href: string, event?: MouseEvent) {
    if (pending.value || working.value || (dirty.value && !persist())) {
      event?.preventDefault();
      return;
    }
    if (
      event &&
      (event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.button !== 0)
    )
      return;
    event?.preventDefault();
    port.navigate(href);
  }
  function search(key: "q" | "values_q" | "spacecraft" | "spacecraft_q", value: string) {
    const query = {
      ...page.value.query,
      [key]: value,
      [key === "q" ? "page" : key === "spacecraft_q" ? "spacecraft_page" : "values_page"]: 1,
    };
    navigate(
      page.value.links.self +
        "?" +
        new URLSearchParams(
          Object.fromEntries(
            Object.entries(query)
              .filter(([, v]) => v !== null)
              .map(([k, v]) => [k, String(v)]),
          ),
        ).toString(),
    );
  }
  function unload(event: BeforeUnloadEvent) {
    if (pending.value || working.value || (dirty.value && !persist())) {
      event.preventDefault();
      event.returnValue = "";
    }
  }
  window.addEventListener("beforeunload", unload);
  onBeforeUnmount(() => {
    active = false;
    generation++;
    window.removeEventListener("beforeunload", unload);
  });
  return {
    page,
    draft,
    current,
    pending,
    confirmed,
    working,
    reading,
    readFailed,
    storageError,
    notice,
    dirty,
    stale,
    locked,
    canSave,
    replace,
    refresh,
    save,
    recover: () => send(true),
    navigate,
    search,
  };
}
