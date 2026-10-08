import type { ScheduleCommand, ScheduleOperation } from "./schedule-service";
import { sameEvidence } from "./contact-schedule";

export type ScheduleMutation =
  | { readonly kind: "submitting" | "unknown"; readonly command: ScheduleCommand }
  | {
      readonly kind: "rejected";
      readonly command: ScheduleCommand;
      readonly reason: "conflict" | "review_changed";
    }
  | {
      readonly kind: "recorded";
      readonly operation: ScheduleOperation;
      readonly command?: ScheduleCommand;
    };

/** A read can advance an operation, but cannot erase an attempt or undo a receipt. */
export function recordOperation(
  previous: ScheduleMutation | undefined,
  operation: ScheduleOperation,
): ScheduleMutation {
  if (previous?.kind === "rejected") return previous;
  const command = previous?.command;
  if (
    command &&
    (command.operationId !== operation.operation_id ||
      command.action !== operation.action ||
      (command.action === "cancel" &&
        command.input.reservation_evidence.reservation_id !== operation.reservation_id))
  )
    throw Error("Different scheduling command");
  if (previous?.kind === "recorded") {
    const prior = previous.operation;
    if (
      prior.operation_id !== operation.operation_id ||
      prior.action !== operation.action ||
      prior.actor_id !== operation.actor_id ||
      prior.reservation_id !== operation.reservation_id ||
      !sameEvidence(prior.context, operation.context)
    )
      throw Error("Changed operation identity");
    if (operation.revision < prior.revision) return previous;
    if (operation.revision === prior.revision) {
      if (!sameEvidence(prior, operation)) throw Error("Conflicting operation revision");
      return previous;
    }
    if (prior.status === "completed" || prior.status === "rejected")
      throw Error("Changed terminal operation");
    if (prior.status === "unconfirmed" && operation.status === "accepted")
      throw Error("Operation regressed");
  }
  return { kind: "recorded", operation, ...(command ? { command } : {}) };
}

export function unresolved(mutation: ScheduleMutation): boolean {
  return (
    mutation.kind !== "rejected" &&
    (mutation.kind !== "recorded" ||
      mutation.operation.status === "accepted" ||
      mutation.operation.status === "unconfirmed")
  );
}
