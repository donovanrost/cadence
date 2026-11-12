import { onScopeDispose, ref, watch, type Ref } from "vue";
import {
  failureOutcome,
  itemLine,
  previewOps,
  type Preview,
  type StageOp,
} from "@/features/changes/index.ts";

export type DryRun =
  | Readonly<{ status: "idle" }>
  | Readonly<{ status: "checking" }>
  | Readonly<{ status: "ready"; preview: Preview; noGo: string | null }>
  | Readonly<{ status: "failed"; text: string }>;

/** C3: the server's dry run of the chosen ops, re-run (debounced) whenever the choice changes. */
export function useRolloutDryRun(missionId: Ref<string>, ops: Ref<readonly StageOp[]>) {
  const dryRun = ref<DryRun>({ status: "idle" });
  let timer: ReturnType<typeof setTimeout> | undefined;
  let controller: AbortController | null = null;
  async function run(current: readonly StageOp[]) {
    controller?.abort();
    controller = new AbortController();
    const signal = controller.signal;
    const r = await previewOps({ missionId: missionId.value, ops: current }, signal);
    if (signal.aborted) return;
    if (!r.ok) {
      dryRun.value = { status: "failed", text: failureOutcome(r.error, "changed").sentence };
      return;
    }
    const blocker = r.value.checks.find((c) => c.verdict === "no_go")?.items[0];
    dryRun.value = {
      status: "ready",
      preview: r.value,
      noGo:
        r.value.verdict === "no_go" ? (blocker ? itemLine(blocker) : "a check says NO-GO.") : null,
    };
  }
  watch(
    ops,
    (current) => {
      clearTimeout(timer);
      controller?.abort();
      if (current.length === 0) return void (dryRun.value = { status: "idle" });
      dryRun.value = { status: "checking" };
      timer = setTimeout(() => void run(current), 400);
    },
    { immediate: true },
  );
  onScopeDispose(() => {
    clearTimeout(timer);
    controller?.abort();
  });
  return dryRun;
}
