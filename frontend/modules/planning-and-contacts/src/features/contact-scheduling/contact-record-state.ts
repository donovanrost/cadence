import { computed } from "vue";
import type { ContactRecord } from "./OpsContactRecord.contracts";
import { useContactWorkflow } from "./contact-workflow-state";
import { onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { ContactRecordPort } from "./OpsContactRecord.contracts";
import { admitContactRecord } from "./contact-record";
export function useContactRecord(input: () => unknown, port?: ContactRecordPort) {
  if (port?.captured) {
    const state = useContactWorkflow(
      input,
      port,
      "record",
      { ...port.context, resource_id: port.context.contact_id },
      {},
    );
    return {
      record: computed(() => state.page.value?.model as ContactRecord | null),
      pending: state.pending,
      notice: state.notice,
      refresh: state.refresh,
      connected: true,
    };
  }
  const record = shallowRef(admitContactRecord(input(), port?.context));
  const pending = ref(false),
    notice = ref("");
  let subject = record.value?.subject,
    generation = 0,
    active = true;
  function replace(value: unknown) {
    const next = admitContactRecord(value, port?.context);
    if (
      !next ||
      (subject && (next.subject.id !== subject.id || next.subject.kind !== subject.kind))
    )
      return false;
    subject ??= next.subject;
    record.value = next;
    return true;
  }
  watch(input, (value) => {
    generation++;
    pending.value = false;
    notice.value = "";
    if (!replace(value)) record.value = null;
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
      const next = await port.refresh();
      if (!active || generation !== run) return;
      notice.value = replace(next)
        ? "Contact evidence refreshed."
        : "Updated contact evidence is unavailable. The previous record is retained.";
    } catch {
      if (active && generation === run)
        notice.value = "Contact evidence could not be refreshed. The previous record is retained.";
    } finally {
      if (active && generation === run) pending.value = false;
    }
  }
  return { record, pending, notice, refresh, connected: !!port };
}
