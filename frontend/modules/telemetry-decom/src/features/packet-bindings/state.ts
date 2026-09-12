import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import {
  admitPacketDocument,
  admitReceipt,
  endpoint,
  id,
  ids,
  record,
  same,
  token,
  validInput,
  type Endpoint,
  type Packet,
  type PacketDocument,
  type PacketPort,
  type PacketReceipt,
  type SelectionInput,
} from "./contracts";
type Draft = { review: string; ids: string[]; endpoint: Endpoint | null; complete: boolean };
type Pending = { key: string; input: SelectionInput };
type Confirmed = { receipt: PacketReceipt; input: SelectionInput };
const contextKeys = [
  "organization_id",
  "mission_id",
  "spacecraft_id",
  "actor_id",
  "installation_id",
] as const;
function scopeEqual(a: unknown, b: PacketDocument["context"]) {
  return record(a) && contextKeys.every((k) => a[k] === b[k]);
}
const baseDraft = (p: PacketDocument): Draft => ({
  review: p.review_token,
  ids: [...p.selection.ids],
  endpoint: p.selection.endpoint
    ? { id: p.selection.endpoint.id, label: p.selection.endpoint.label }
    : null,
  complete: p.selection.complete,
});
function tabStorage(): Storage | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}
export function usePacketBindings(
  initial: () => PacketDocument,
  port: PacketPort,
  storage = tabStorage(),
) {
  const first = initial(),
    page = shallowRef(first),
    draft = ref<Draft>(baseDraft(first));
  const pending = shallowRef<Pending | null>(null),
    confirmed = shallowRef<Confirmed | null>(null);
  const working = ref(false),
    reading = ref(false),
    readFailed = ref(false),
    notice = ref(""),
    storageProblem = ref("");
  const key =
    "cadence.telemetry-decom.packet-draft.v1:" +
    JSON.stringify(contextKeys.map((k) => first.context[k]));
  let active = true,
    generation = 0;
  const stale = computed(() => draft.value.review !== page.value.review_token);
  const dirty = computed(
    () =>
      !same([...draft.value.ids].sort(), [...page.value.selection.ids].sort()) ||
      draft.value.endpoint?.id !== page.value.selection.endpoint?.id ||
      draft.value.complete !== page.value.selection.complete,
  );
  const locked = computed(
    () => working.value || !!pending.value || reading.value || !!storageProblem.value,
  );
  const unavailable = computed(() =>
    draft.value.ids.filter((id) => page.value.selection.unavailable_ids.includes(id)),
  );
  const canSave = computed(
    () =>
      !locked.value &&
      !stale.value &&
      !readFailed.value &&
      !!page.value.configuration &&
      draft.value.complete &&
      !!draft.value.endpoint &&
      draft.value.ids.length >= 1 &&
      draft.value.ids.length <= 512 &&
      !unavailable.value.length,
  );

  function persist(): boolean {
    try {
      if (!storage) throw Error("storage unavailable");
      storage.setItem(
        key,
        JSON.stringify({
          version: 1,
          context: first.context,
          draft: draft.value,
          pending: pending.value,
          confirmed: confirmed.value,
        }),
      );
      storageProblem.value = "";
      return true;
    } catch {
      storageProblem.value =
        "This tab could not preserve the draft and pending save. Refresh before saving or leaving this page.";
      return false;
    }
  }
  function restore() {
    try {
      const raw = storage?.getItem(key);
      if (!raw) return;
      if (raw.length > 1024 * 1024) throw Error("oversized draft");
      const saved: unknown = JSON.parse(raw);
      if (
        !record(saved) ||
        saved.version !== 1 ||
        !scopeEqual(saved.context, first.context) ||
        !record(saved.draft)
      )
        throw Error("invalid draft");
      const d = saved.draft;
      if (
        !token(d.review) ||
        !ids(d.ids) ||
        !(d.endpoint === null || endpoint(d.endpoint)) ||
        typeof d.complete !== "boolean"
      )
        throw Error("invalid draft");
      if (
        saved.pending !== null &&
        (!record(saved.pending) || !id(saved.pending.key) || !validInput(saved.pending.input))
      )
        throw Error("invalid pending save");
      if (
        saved.confirmed !== null &&
        (!record(saved.confirmed) ||
          !validInput(saved.confirmed.input) ||
          !admitReceipt(saved.confirmed.receipt, saved.confirmed.input))
      )
        throw Error("invalid receipt");
      draft.value = d as Draft;
      pending.value = saved.pending as Pending | null;
      confirmed.value = saved.confirmed as Confirmed | null;
      if (pending.value)
        notice.value =
          "A save is awaiting confirmation. Recover its response before editing or submitting again.";
    } catch {
      storageProblem.value =
        "Saved work in this tab could not be recovered. Open a new tab to review saved bindings before making another change.";
    }
  }
  function adopt(p: PacketDocument) {
    draft.value = baseDraft(p);
    readFailed.value = false;
    persist();
  }
  function accept(value: unknown): boolean {
    const next = admitPacketDocument(value);
    if (!next || !scopeEqual(next.context, first.context)) return false;
    page.value = next;
    readFailed.value = false;
    const receipt = confirmed.value;
    if (
      !pending.value &&
      receipt &&
      draft.value.review === receipt.input.expected_review &&
      same([...draft.value.ids].sort(), [...receipt.input.selected_packet_ids].sort()) &&
      draft.value.endpoint?.id === receipt.input.source_endpoint_ref &&
      next.configuration?.id === receipt.receipt.result.configurationId &&
      next.configuration.version === receipt.receipt.result.configurationVersion &&
      same([...next.selection.ids].sort(), [...receipt.input.selected_packet_ids].sort()) &&
      next.selection.endpoint?.id === receipt.input.source_endpoint_ref
    )
      adopt(next);
    return true;
  }
  restore();
  accept(first);
  watch(initial, (value) => {
    if (!accept(value)) readFailed.value = true;
  });
  onBeforeUnmount(() => {
    active = false;
    generation++;
    window.removeEventListener("beforeunload", guardUnload);
  });
  function guardUnload(event: BeforeUnloadEvent) {
    if (working.value || pending.value || (dirty.value && !persist())) {
      event.preventDefault();
      event.returnValue = "";
    }
  }
  window.addEventListener("beforeunload", guardUnload);

  function choosePacket(packet: Packet, checked: boolean) {
    if (
      locked.value ||
      stale.value ||
      !draft.value.complete ||
      !packet.selectable ||
      !page.value.packets.items.some((p) => p.id === packet.id)
    )
      return;
    const selection = new Set(draft.value.ids);
    if (checked) selection.add(packet.id);
    else selection.delete(packet.id);
    if (selection.size > 512) {
      notice.value = "Select at most 512 packets.";
      return;
    }
    draft.value = { ...draft.value, ids: [...selection].sort() };
    persist();
  }
  function chooseEndpoint(value: Endpoint | null) {
    if (
      locked.value ||
      stale.value ||
      (value && !page.value.endpoints.items.some((e) => e.id === value.id))
    )
      return;
    draft.value = { ...draft.value, endpoint: value ? { id: value.id, label: value.label } : null };
    persist();
  }
  function clearUnavailable() {
    if (locked.value || stale.value) return;
    draft.value = {
      ...draft.value,
      ids: draft.value.ids.filter((id) => !unavailable.value.includes(id)),
    };
    persist();
  }
  function clearSelection() {
    if (
      locked.value ||
      stale.value ||
      !window.confirm(
        "Clear the entire draft selection? Saved bindings remain unchanged until you save a new selection.",
      )
    )
      return;
    draft.value = { ...draft.value, ids: [], complete: true };
    persist();
  }
  function reviewCurrent() {
    if (pending.value || working.value) return;
    if (
      (dirty.value || stale.value) &&
      !window.confirm("Replace this draft with the current saved selection?")
    )
      return;
    adopt(page.value);
    notice.value = "Current saved bindings loaded for review.";
  }
  async function refresh() {
    if (working.value) return;
    const current = ++generation;
    reading.value = true;
    try {
      const value = await port.read();
      if (!active || current !== generation) return;
      if (!accept(value)) throw Error("invalid document");
      notice.value = pending.value
        ? "Saved bindings refreshed. Recover the pending save response before editing."
        : "Saved bindings refreshed. Your draft was retained.";
    } catch {
      if (active && current === generation) {
        readFailed.value = true;
        notice.value =
          "Current bindings could not be read. Your draft is retained; refresh before saving.";
      }
    } finally {
      if (active && current === generation) reading.value = false;
    }
  }
  async function send(recovery = true) {
    const intent = pending.value;
    if (!intent || working.value) return;
    working.value = true;
    notice.value = "Saving packet bindings…";
    let completed = false;
    try {
      const response = await port.save(intent.input, intent.key);
      if (!active) return;
      const receipt = admitReceipt(response, intent.input);
      if (!receipt) throw Error("unconfirmed receipt");
      completed = true;
      confirmed.value = { receipt, input: intent.input };
      pending.value = null;
      persist();
      notice.value = "Packet bindings saved. Refreshing their current state…";
    } catch (error) {
      if (!active) return;
      if (
        record(error) &&
        typeof error.code === "string" &&
        [
          "review_conflict",
          "review_required",
          "packet_binding_version_conflict",
          "invalid_input",
          "forbidden",
          "application_unavailable",
          "unsupported_action",
        ].includes(error.code) &&
        (!recovery ||
          ["review_conflict", "review_required", "packet_binding_version_conflict"].includes(
            error.code,
          ))
      ) {
        pending.value = null;
        readFailed.value = true;
        persist();
        notice.value =
          error instanceof Error
            ? error.message
            : "The save was rejected. Refresh and review current bindings.";
      } else {
        notice.value =
          "The save response could not be confirmed. Recover that same save before making another change.";
        persist();
      }
    } finally {
      if (active) working.value = false;
    }
    if (active && completed) await refresh();
  }
  async function save() {
    if (!canSave.value) return;
    const config = page.value.configuration!;
    const input: SelectionInput = {
      expected_review: draft.value.review,
      expected_configuration_version: config.version,
      input_id: "telemetry-fields",
      input_version: 1,
      catalog_revision_id: config.catalog_revision_id,
      source_endpoint_ref: draft.value.endpoint!.id,
      selected_packet_ids: [...draft.value.ids],
    };
    pending.value = { key: crypto.randomUUID(), input };
    if (!persist()) {
      pending.value = null;
      return;
    }
    await send(false);
  }
  function navigate(href: string, event?: MouseEvent) {
    if (working.value || pending.value || (dirty.value && !persist())) {
      event?.preventDefault();
      return;
    }
    if (
      event &&
      (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0)
    )
      return;
    event?.preventDefault();
    port.navigate(href);
  }
  function search(kind: "q" | "endpoint_q", text: string) {
    const query = {
      ...page.value.query,
      [kind]: text,
      [kind === "q" ? "page" : "endpoint_page"]: 1,
    };
    navigate(
      page.value.links.self +
        "?" +
        new URLSearchParams(
          Object.fromEntries(Object.entries(query).map(([k, v]) => [k, String(v)])),
        ).toString(),
    );
  }
  return {
    page,
    draft,
    pending,
    confirmed,
    working,
    reading,
    readFailed,
    notice,
    storageProblem,
    stale,
    dirty,
    locked,
    unavailable,
    canSave,
    choosePacket,
    chooseEndpoint,
    clearUnavailable,
    clearSelection,
    reviewCurrent,
    refresh,
    save,
    recover: () => send(true),
    navigate,
    search,
  };
}
