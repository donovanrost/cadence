import { computed, onBeforeUnmount, onErrorCaptured, ref, shallowRef, watch } from "vue";
import {
  reportFrontendFailure,
  type FrontendDiagnostic,
  type FrontendFailureKind,
} from "../frontend-diagnostics";
import type { PageContext } from "./page-admission";

export function usePageBoundary(
  input: {
    snapshot: unknown;
    contributionId: string;
    context: PageContext;
    refresh: () => Promise<void>;
    refreshing?: boolean;
  },
  boundary: string,
) {
  let alive = true,
    generation = 0;
  const reported = new Set<FrontendFailureKind>();
  const failure = shallowRef<FrontendDiagnostic | null>(null);
  const retrying = ref(false);
  const crashed = ref(false);
  function report(kind: FrontendFailureKind, cause: unknown) {
    if (!alive || reported.has(kind)) return;
    reported.add(kind);
    if (kind === "render") crashed.value = true;
    failure.value = reportFrontendFailure(
      { boundary, contributionId: input.contributionId, version: 1, ...input.context },
      kind,
      cause,
    );
  }
  watch(
    () => [input.snapshot, input.context, input.contributionId],
    () => {
      generation++;
      reported.clear();
      failure.value = null;
      crashed.value = false;
      retrying.value = false;
    },
    { flush: "sync" },
  );
  onErrorCaptured((cause) => {
    report("render", cause);
    return false;
  });
  onBeforeUnmount(() => {
    alive = false;
    generation++;
  });
  async function retry() {
    if (!alive || retrying.value || input.refreshing) return;
    const current = generation;
    retrying.value = true;
    try {
      await input.refresh();
    } catch (cause) {
      if (current === generation) report("retry", cause);
    } finally {
      if (alive && current === generation) retrying.value = false;
    }
  }
  return {
    report,
    retry,
    retrying,
    alive: () => alive,
    crashed,
    diagnosticId: computed(() => failure.value?.id),
  };
}
