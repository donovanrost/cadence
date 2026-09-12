import { computed, onBeforeUnmount, ref, shallowRef } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  monitorHref,
  reviewHref,
  queueInput,
  readOperation,
  readQueuePage,
  type QueuePage,
  type Operation,
  type Preview,
} from "./contracts";
export function useQueueSubmission(
  initial: QueuePage,
  port: OpsPagePort,
  readPort: OpsPageReadPort,
) {
  const page = shallowRef(initial),
    operation = shallowRef<Operation | null>(initial.operation);
  const submitted = shallowRef<Preview | null>(initial.operation ? initial.preview : null);
  const busy = ref(false),
    reading = ref(false),
    confirmed = ref(false),
    feedback = ref("");
  const context = { ...initial.model.context },
    actor = initial.model.actor_id;
  const model = computed(() => page.value.model),
    preview = computed(() => page.value.preview);
  const request = computed(
    () => submitted.value?.request ?? preview.value?.request ?? model.value.request,
  );
  const locked = computed(() => busy.value || reading.value || !!operation.value);
  const canQueue = computed(
    () => model.value.availability === "available" && !!preview.value && !locked.value,
  );
  let disposed = false;
  const unguard = port.guardNavigation?.(() => !busy.value && !reading.value);
  onBeforeUnmount(() => {
    disposed = true;
    unguard?.();
  });
  async function submit() {
    if (!canQueue.value || !confirmed.value || !preview.value) return;
    const expected = preview.value;
    submitted.value = expected;
    operation.value = { status: "unconfirmed" };
    busy.value = true;
    feedback.value = "";
    try {
      const result = readOperation(await port.execute("submit", queueInput(expected)), expected);
      if (!disposed) operation.value = result;
    } catch {
      /* Preserve the consumed, unconfirmed operation until receipt recovery. */
    } finally {
      if (!disposed) busy.value = false;
    }
  }
  async function refresh() {
    if (busy.value || reading.value) return;
    reading.value = true;
    feedback.value = "";
    try {
      const next = readQueuePage(await readPort.read(), context);
      if (next.model.actor_id !== actor) throw Error();
      if (submitted.value) {
        const expected = submitted.value;
        if (
          !next.preview ||
          next.preview.token !== expected.token ||
          next.preview.operation_id !== expected.operation_id ||
          next.preview.approval.basis_sha256 !== expected.approval.basis_sha256 ||
          !next.operation
        )
          throw Error();
        const result = readOperation(next.operation, expected);
        if (
          operation.value?.status === "completed" &&
          (result.status !== "completed" ||
            (
              [
                "operation_id",
                "queue_id",
                "request_id",
                "actor_id",
                "enqueued_at",
                "approved_content_sha256",
              ] as const
            ).some(
              (key) =>
                result.receipt[key] !==
                (operation.value?.status === "completed" ? operation.value.receipt[key] : null),
            ))
        )
          throw Error();
        if (operation.value?.status === "rejected" && result.status !== "rejected") throw Error();
      }
      if (!disposed) {
        page.value = next;
        operation.value = next.operation;
        confirmed.value = false;
      }
    } catch {
      if (!disposed)
        feedback.value = operation.value
          ? "The queue result could not be refreshed. This attempt will not be sent again."
          : "The request could not be refreshed. Review its current state before queueing.";
    } finally {
      if (!disposed) reading.value = false;
    }
  }
  function follow(event: MouseEvent, url: string) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
      return;
    event.preventDefault();
    if (!busy.value && !reading.value) port.navigate(url);
  }
  return {
    model,
    preview,
    request,
    operation,
    busy,
    reading,
    confirmed,
    feedback,
    locked,
    canQueue,
    monitor: monitorHref(context),
    review: reviewHref(context),
    submit,
    refresh,
    follow,
  };
}
