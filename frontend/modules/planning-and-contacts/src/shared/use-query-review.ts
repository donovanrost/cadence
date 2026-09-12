import { computed, onBeforeUnmount, ref, shallowRef, watch, type ShallowRef } from "vue";
import { validReviewReason, type RemoteQueryProtocol } from "./workflow-protocol";

type ReviewPort<Q extends [string, Record<string, unknown>]> = RemoteQueryProtocol & {
  execute(...request: Q): Promise<unknown>;
  refresh(): Promise<unknown>;
};
type ReviewOptions<
  M,
  Q extends [string, Record<string, unknown>],
  R extends Record<string, string>,
  C,
> = {
  admit(value: unknown): M | null;
  subject(model: M): string;
  identity(model: M): string;
  reasons(): R;
  canAct(model: M, action: Q[0]): boolean;
  reasonRequired(action: Q[0]): boolean;
  request(model: M, action: Q[0], reason: string): Q;
  completion(value: unknown, model: M, action: Q[0]): C | null;
  reconciled(model: M, confirmation: C): boolean;
};

/** Shared remote-query lifecycle. Page-ledger recovery belongs to its separate protocol. */
export function useQueryReview<
  M,
  Q extends [string, Record<string, unknown>],
  R extends Record<string, string>,
  C,
>(input: () => unknown, port: ReviewPort<Q> | undefined, options: ReviewOptions<M, Q, R, C>) {
  const detail: ShallowRef<M | null> = shallowRef(options.admit(input()));
  const reasons = ref(options.reasons());
  const pending = ref(false),
    locked = ref(false),
    notice = ref("");
  let generation = 0,
    active = true;
  let confirmed: C | null = null;
  let subject = detail.value ? options.subject(detail.value) : undefined;
  function replace(value: unknown) {
    let next = options.admit(value);
    if (next && subject && options.subject(next) !== subject) next = null;
    if (!next || !detail.value || options.identity(next) !== options.identity(detail.value))
      reasons.value = options.reasons();
    if (next) subject ??= options.subject(next);
    detail.value = next;
  }
  const current = (run: number) => active && run === generation;
  const reconciled = () =>
    confirmed !== null && detail.value !== null && options.reconciled(detail.value, confirmed);
  watch(input, (value) => {
    if (pending.value) locked.value = true;
    generation++;
    pending.value = false;
    replace(value);
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
      const value = await port.refresh();
      if (!current(run)) return;
      replace(value);
      if (reconciled()) locked.value = false;
      notice.value = !locked.value
        ? "Review refreshed."
        : confirmed
          ? "Decision completed, but its updated evidence is not yet available. Further decisions remain disabled."
          : "Review refreshed. The previous operation has an uncertain outcome; another submission remains disabled.";
    } catch {
      if (current(run)) notice.value = "Review could not be refreshed. Your reasons are retained.";
    } finally {
      if (current(run)) pending.value = false;
    }
  }
  const enabled = (action: Q[0]) =>
    !!port &&
    detail.value !== null &&
    !pending.value &&
    !locked.value &&
    options.canAct(detail.value, action);
  async function execute(action: Q[0], reason = "") {
    const model = detail.value;
    if (!model || !port || !enabled(action)) return;
    if (options.reasonRequired(action) && !validReviewReason(reason)) {
      notice.value = "Enter a reason of at most 4096 bytes.";
      return;
    }
    const run = ++generation;
    confirmed = null;
    pending.value = true;
    notice.value = "Sending the reviewed decision…";
    try {
      const response = await port.execute(...options.request(model, action, reason));
      if (!current(run)) return;
      const completion = options.completion(response, model, action);
      if (completion === null) throw Error("Uncertain receipt");
      confirmed = completion;
      reasons.value = options.reasons();
      locked.value = true;
      try {
        const value = await port.refresh();
        if (!current(run)) return;
        replace(value);
        locked.value = !reconciled();
        notice.value =
          detail.value && !locked.value
            ? "Decision completed. Review updated."
            : "Decision completed, but the refreshed review was unavailable.";
      } catch {
        if (current(run))
          notice.value = "Decision completed. Refresh the review before continuing.";
      }
    } catch {
      if (!current(run)) return;
      locked.value = true;
      notice.value =
        "The operation could not be confirmed. Keep this review open and refresh its evidence; do not submit it again.";
    } finally {
      if (current(run)) pending.value = false;
    }
  }
  return {
    detail,
    reasons,
    pending,
    locked,
    notice,
    enabled,
    execute,
    refresh,
    connected: computed(() => !!port),
  };
}
