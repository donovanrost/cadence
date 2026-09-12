import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import {
  fields,
  href,
  id,
  record,
  text,
  type Context,
  type Thresholds,
} from "../../shared/contracts";
import {
  admitDocument,
  admitReceipt,
  validInput,
  type DefinitionInput,
  type DefinitionReceipt,
  type DefinitionsDocument,
  type DefinitionsPort,
} from "./contracts";
const empty = (): DefinitionInput => ({
  point_id: "",
  limit_set_name: "",
  red_low: "",
  yellow_low: "",
  yellow_high: "",
  red_high: "",
  expected_definition_id: null,
  expected_version: 0,
  expected_activation_event_id: null,
});
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
const scopeKeys = ["organization_id", "mission_id", "actor_id", "installation_id"] as const;
const sameScope = (a: unknown, b: Context) => record(a) && scopeKeys.every((k) => a[k] === b[k]);
const messages: Record<string, string> = {
  review_conflict:
    "This definition or its activation changed. Refresh and review it before saving.",
  review_required: "Review the current point and limit set before saving.",
  invalid_number: "Enter a supported number for each configured threshold.",
  invalid_threshold_order: "Thresholds must increase from red low through red high.",
  threshold_required: "Configure at least one threshold.",
  required_field: "A point ID and limit set are required.",
  invalid_field: "Check the point ID and limit set length.",
  invalid_definition: "The definition could not be saved and activated. Review the retained draft.",
  forbidden: "You no longer have permission to save limits. Your draft is retained.",
  application_unavailable: "Limits is unavailable in this mission. Your draft is retained.",
  unsupported_action: "This editor is no longer supported. Refresh before saving.",
  invalid_input: "The request was rejected. Review the retained draft before saving.",
};
export function useDefinitions(initial: () => DefinitionsDocument, port: DefinitionsPort) {
  const first = initial(),
    page = shallowRef(first),
    draft = ref(empty()),
    baseline = ref(empty());
  const identity = ref({
    point: first.editor?.point_id || "",
    set: first.editor?.limit_set_name || "DEFAULT",
  });
  const pending = shallowRef<{ key: string; input: DefinitionInput } | null>(null),
    confirmed = shallowRef<DefinitionReceipt | null>(null),
    confirmedInput = shallowRef<DefinitionInput | null>(null);
  const working = ref(false),
    reading = ref(false),
    readFailed = ref(false),
    storageError = ref(""),
    notice = ref("");
  let alive = true,
    generation = 0;
  const key =
    "cadence.limits.definition-draft.v1:" + JSON.stringify(scopeKeys.map((k) => first.context[k]));
  let journal: Storage | null = null;
  try {
    journal = window.sessionStorage;
  } catch {
    /* Saving stays disabled until a journal is available. */
  }
  const dirty = computed(() => !same(draft.value, baseline.value));
  const stale = computed(() => {
    const e = page.value.editor,
      d = draft.value;
    return (
      (!!confirmed.value &&
        confirmed.value.result.pointId === d.point_id &&
        confirmed.value.result.limitSetName === d.limit_set_name &&
        d.expected_version < confirmed.value.result.version) ||
      !e ||
      e.point_id !== d.point_id ||
      e.limit_set_name !== d.limit_set_name ||
      e.review.definition_id !== d.expected_definition_id ||
      e.review.version !== d.expected_version ||
      e.review.activation_event_id !== d.expected_activation_event_id
    );
  });
  const locked = computed(
    () => working.value || reading.value || !!pending.value || !!storageError.value,
  );
  const normalized = (): DefinitionInput => ({
    ...draft.value,
    ...Object.fromEntries(fields.map((k) => [k, draft.value[k].trim()])),
  });
  const canSave = computed(
    () => !locked.value && !readFailed.value && !stale.value && validInput(normalized()),
  );
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
          identity: identity.value,
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
      Object.keys(v).length === 9 &&
      text(v.point_id) &&
      text(v.limit_set_name) &&
      fields.every((k) => text(v[k], 80)) &&
      Number.isSafeInteger(v.expected_version) &&
      (v.expected_version as number) >= 0 &&
      (v.expected_definition_id === null || id(v.expected_definition_id)) &&
      (v.expected_activation_event_id === null || id(v.expected_activation_event_id))
    );
  }
  try {
    const raw = journal?.getItem(key);
    if (raw) {
      if (raw.length > 40000) throw Error();
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
      if (saved.identity !== undefined) {
        if (!record(saved.identity) || !text(saved.identity.point) || !text(saved.identity.set))
          throw Error();
        identity.value = { point: saved.identity.point, set: saved.identity.set };
      }
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
      "This tab's saved work could not be recovered. Use a new tab to review current limits before making another change.";
  }
  watch(
    [draft, identity],
    () => {
      if (!working.value) persist();
    },
    { deep: true, flush: "sync" },
  );
  function adopt(thresholds?: Thresholds) {
    const e = page.value.editor;
    if (locked.value || readFailed.value || !e) return;
    if (
      dirty.value &&
      !window.confirm("Replace this unsaved threshold draft with the reviewed definition?")
    )
      return;
    const next: DefinitionInput = {
      ...empty(),
      point_id: e.point_id,
      limit_set_name: e.limit_set_name,
      expected_definition_id: e.review.definition_id,
      expected_version: e.review.version,
      expected_activation_event_id: e.review.activation_event_id,
    };
    for (const k of fields)
      next[k] = e.current?.thresholds[k] === undefined ? "" : String(e.current.thresholds[k]);
    baseline.value = { ...next };
    if (thresholds)
      for (const k of fields) next[k] = thresholds[k] === undefined ? "" : String(thresholds[k]);
    draft.value = next;
    notice.value = `Reviewing ${e.point_id} · ${e.limit_set_name}. Saving creates and activates version ${e.review.version + 1}.`;
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
      if (!alive || n !== generation) return;
      if (!accept(value)) throw Error();
      notice.value = pending.value
        ? "Evidence refreshed. Recover the pending save before editing."
        : "Evidence refreshed. Your draft is retained; review it before saving.";
    } catch {
      if (alive && n === generation) {
        readFailed.value = true;
        notice.value = "Current evidence could not be read. Your draft is retained.";
      }
    } finally {
      if (alive && n === generation) reading.value = false;
    }
  }
  async function send(recovery = true) {
    const intent = pending.value;
    if (!intent || working.value) return;
    working.value = true;
    let completed = false;
    try {
      const result = await port.save(intent.input, intent.key);
      if (!alive) return;
      const receipt = admitReceipt(result, intent.input);
      if (!receipt) throw Error();
      confirmed.value = receipt;
      confirmedInput.value = intent.input;
      pending.value = null;
      baseline.value = { ...intent.input };
      draft.value = { ...intent.input };
      completed = true;
      persist();
      notice.value = `Version ${receipt.result.version} saved and activated. Refresh and review before another save.`;
    } catch (e) {
      if (!alive) return;
      const code = record(e) && typeof e.code === "string" ? e.code : "";
      if (
        [
          "review_conflict",
          "review_required",
          "invalid_number",
          "invalid_threshold_order",
          "threshold_required",
          "required_field",
          "invalid_field",
          "invalid_definition",
        ].includes(code) ||
        (!recovery &&
          ["forbidden", "application_unavailable", "unsupported_action", "invalid_input"].includes(
            code,
          ))
      ) {
        pending.value = null;
        readFailed.value = true;
        notice.value = messages[code];
      } else
        notice.value =
          "The save response is unconfirmed. Recover this same save before making another change.";
      persist();
    } finally {
      if (alive) working.value = false;
    }
    if (alive && completed) await refresh();
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
  function navigate(target: string, event?: MouseEvent) {
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
    port.navigate(target);
  }
  function search(k: "q" | "points_q", value: string) {
    navigate(
      href(page.value.links.self, {
        ...page.value.query,
        [k]: value,
        [k === "q" ? "page" : "points_page"]: 1,
      }),
    );
  }
  function choose(point: string, set: string) {
    navigate(
      href(page.value.links.self, {
        ...page.value.query,
        point: point.trim(),
        set: set.trim() || "DEFAULT",
        definition: "",
        version: null,
        history_page: 1,
        activation_page: 1,
      }),
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
    alive = false;
    generation++;
    window.removeEventListener("beforeunload", unload);
  });
  return {
    page,
    identity,
    draft,
    dirty,
    pending,
    confirmed,
    working,
    reading,
    readFailed,
    storageError,
    notice,
    locked,
    stale,
    canSave,
    adopt,
    refresh,
    save,
    recover: () => send(true),
    navigate,
    search,
    choose,
  };
}
