import { onBeforeUnmount, ref, shallowRef, watch } from "vue";
import {
  admitContactPage,
  admitContactOperation,
  equalContact as equal,
  contactFeedback,
  type CapturedContact,
  type ContactAction,
  type ContactContext,
  type ContactKind,
  type ContactOperation,
  type ContactPage,
} from "./contact-workflow";

export function useContactWorkflow(
  input: () => unknown,
  port: {
    captured?: CapturedContact;
    refresh(): Promise<unknown>;
  },
  kind: ContactKind,
  context: ContactContext,
  options: {
    execute?: (action: ContactAction, input: Record<string, unknown>) => Promise<unknown>;
    reconciled?: (op: ContactOperation, page: ContactPage) => boolean;
    completed?: (op: ContactOperation) => void;
  },
) {
  const actor = port.captured!.actorId;
  const initial = admitContactPage(kind, input(), context, actor);
  const page = shallowRef(initial),
    pending = ref(false),
    locked = ref(!initial),
    notice = ref("");
  const confirmed = shallowRef<ContactOperation | null>(
    initial?.operation?.status === "completed" ? initial.operation : null,
  );
  let sequence = initial?.sequence ?? 0,
    operation = initial?.operation ?? null;
  let attempted: Pick<ContactOperation, "sequence" | "action" | "input"> | null = operation;
  let active = true,
    generation = 0,
    effectPending = false;
  let pinnedQuery = initial?.model.query,
    pinnedSelection = selected(initial);
  if (operation)
    locked.value =
      operation.status !== "rejected" &&
      !(operation.status === "completed" && options.reconciled?.(operation, initial!));
  function selected(p: ContactPage | null) {
    if (p?.kind !== "reservation") return null;
    const s = (p.model as any).selected;
    return s ? [s.id, s.proposal_hash, s.provider_revision] : null;
  }
  function matches(op: ContactOperation) {
    return (
      attempted &&
      op.sequence === attempted.sequence &&
      op.action === attempted.action &&
      equal(op.input, attempted.input)
    );
  }
  function settle(op: ContactOperation) {
    if (!matches(op)) throw Error("Different contact operation");
    const priorReservation = operation?.receipt?.result.value.providerReservationId;
    if (
      op.receipt?.result.source === "observed" &&
      priorReservation &&
      op.receipt.result.value.providerReservationId !== priorReservation
    )
      throw Error("Different recovered reservation");
    operation = op;
    sequence = op.sequence;
    locked.value = true;
    if (op.status === "completed") {
      confirmed.value = op;
      options.completed?.(op);
      notice.value =
        op.receipt?.result.source === "observed"
          ? "The reservation now has a confirmed provider state. Refreshing its evidence…"
          : "The operation returned a recorded result. Refreshing its evidence…";
    } else
      notice.value =
        op.status === "rejected"
          ? (op.feedback ?? []).map((k) => contactFeedback[k]).join(" ")
          : "The provider outcome remains unconfirmed. Refresh to check its recorded evidence.";
  }
  function accept(value: unknown) {
    const next = admitContactPage(kind, value, context, actor);
    if (!next || next.sequence < sequence) throw Error("Unavailable contact evidence");
    const key = kind === "record" ? "revision" : kind === "reservation" ? "change_id" : null;
    const q: any = { ...pinnedQuery };
    if (key && q[key] === null) q[key] = (next.model.query as any)[key];
    if (pinnedQuery && !equal(q, next.model.query)) throw Error("Different review query");
    if (pinnedSelection && !equal(pinnedSelection, selected(next)))
      throw Error("Different provider proposal");
    if (next.sequence === sequence && !equal(operation, next.operation)) {
      if (
        operation?.status !== "unconfirmed" ||
        next.operation?.status !== "completed" ||
        next.operation.receipt?.result.source !== "observed"
      )
        throw Error("Changed operation");
      settle(next.operation);
    } else if (next.sequence > sequence) {
      if (!next.operation) throw Error("Missing operation");
      settle(next.operation);
    }
    if (attempted && next.sequence < attempted.sequence)
      throw Error("The attempted operation is not recorded");
    pinnedQuery = next.model.query;
    pinnedSelection ??= selected(next);
    page.value = next;
    locked.value =
      operation !== null &&
      operation.status !== "rejected" &&
      !(operation.status === "completed" && options.reconciled?.(operation, next));
    if (!locked.value && operation?.status === "completed")
      notice.value = "Recorded result and current evidence verified.";
  }
  async function read(run: number) {
    const next = await port.refresh();
    if (!active || run !== generation) return;
    accept(next);
  }
  async function refresh() {
    if (pending.value) return;
    const run = ++generation;
    pending.value = true;
    try {
      await read(run);
      if (active && run === generation && !locked.value && !operation)
        notice.value = "Contact evidence refreshed.";
    } catch {
      if (active && run === generation)
        notice.value =
          "Updated evidence is unavailable. Your previous review, drafts and recorded results are retained.";
    } finally {
      if (active && run === generation) pending.value = false;
    }
  }
  async function execute(action: ContactAction, payload: Record<string, unknown>) {
    if (!options.execute || !page.value || pending.value || locked.value) return;
    const run = ++generation;
    attempted = { sequence: sequence + 1, action, input: JSON.parse(JSON.stringify(payload)) };
    pending.value = true;
    effectPending = true;
    locked.value = true;
    notice.value = "Sending the reviewed operation…";
    try {
      const value = await options.execute(action, {
        sequence: attempted.sequence,
        payload: attempted.input,
      });
      if (!active || generation !== run) return;
      const op = admitContactOperation(value, page.value);
      if (!op) throw Error("Unverified operation result");
      settle(op);
      page.value = { ...page.value, sequence, operation: op };
      await read(run);
    } catch {
      if (active && generation === run)
        notice.value =
          "No verified completion was received. Keep this review open and refresh before another operation.";
    } finally {
      if (active && generation === run) {
        pending.value = false;
        effectPending = false;
      }
    }
  }
  watch(input, (value) => {
    if (pending.value || equal(value, initial)) return;
    try {
      accept(value);
    } catch {
      notice.value =
        "Updated evidence could not be admitted. Previous evidence and drafts are retained.";
    }
  });
  const release = port.captured!.guardNavigation?.(() => !effectPending);
  onBeforeUnmount(() => {
    active = false;
    generation++;
    release?.();
  });
  return { page, pending, locked, notice, confirmed, refresh, execute };
}
