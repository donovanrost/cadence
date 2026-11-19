<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { ApButton, ApCallout, ApPanel, focusFirstConnected, refocusFirst } from "@/ui";
import type { ModelKey, ModelRevision } from "./api.ts";
import ApprovalActions from "./ApprovalActions.vue";
import ApprovalFacts from "./ApprovalFacts.vue";
import ComparisonReport from "./ComparisonReport.vue";
import RejectSheet from "./RejectSheet.vue";
import { useApproval } from "./useApproval.ts";
import {
  cannotApproveLine,
  cannotDecideLine,
  decidedLine,
  NO_EARLIER_APPROVE,
  noEarlierLine,
  REPLAY_NOT_RUN,
  unwordedBlockCode,
} from "./words.ts";

/**
 * ux U65 Approval · catalog rev N: the comparison against the revision it would replace, who
 * imported it, and Approve / Reject…. Decided: one line, the report behind Show report.
 */
const props = defineProps<{ revision: ModelRevision; modelKey: ModelKey }>();
const emit = defineEmits<{ changed: [] }>();
const rev = computed(() => props.revision.catalog_revision?.number ?? null);
const report = computed(() => props.revision.comparison);
const revWord = computed(() => (rev.value === null ? "this revision" : `rev ${rev.value}`));
const title = computed(() =>
  rev.value === null ? "Approval" : `Approval · catalog rev ${rev.value}`,
);
const meta = computed(() => {
  const r = report.value;
  if (!r) return undefined;
  // U90: nothing earlier to compare with.
  return r.against
    ? `AGAINST REV ${r.against.catalog_revision_number}`
    : "NO EARLIER CONFIGURATION";
});
const noEarlier = computed(() => (report.value ? noEarlierLine(report.value) : null));
const decided = computed(() => decidedLine(props.revision));
const blocked = computed(() => cannotDecideLine(props.revision));
const approveBlocked = computed(() => cannotApproveLine(props.revision));
/** #308 (d): a blocked reason the console doesn't word; its code is in Technical details. */
const blockCode = computed(() => unwordedBlockCode(props.revision));
const showReport = ref(false);
/** U88: Setup › Catalog, where its file can be imported as a new catalog revision. */
const CATALOG = { name: "setup.catalog" } as const;
const sheet = ref<InstanceType<typeof RejectSheet> | null>(null);
const act = useApproval(
  computed(() => props.modelKey),
  () => rev.value,
  () => emit("changed"),
);
const panelFailure = computed(() =>
  act.failure.value && act.failure.value.from !== "reject" ? act.failure.value : null,
);
async function reject(reason: string) {
  if (await act.reject(reason)) sheet.value?.close();
}
// a11y A5: a decision or an arriving report swaps out the focused control (Approve, Reject…'s
// returned focus, Run comparison); land on the decided line, else the now-enabled Approve.
const mark = (name: string) => document.querySelector<HTMLElement>(`[data-approval-${name}]`);
watch(
  [decided, () => report.value?.report_id],
  () => refocusFirst(mark("decided"), mark("approve")),
  { flush: "post" },
);
/** The failure callout's Run comparison clears the callout it sits in, so focus the actions' own first. */
function runAgain() {
  focusFirstConnected(mark("run"));
  void act.run();
}
</script>

<template>
  <ApPanel index="A1" :title="title" :meta="meta">
    <!-- U90: at the top, above the replay callout, decided or not. -->
    <!-- C12 (#313): decided, U90 keeps its short form; the full callout is for the decision. -->
    <p v-if="noEarlier && decided" class="m-0 mb-2 text-sm text-text-3">
      Not compared: no earlier configuration.
    </p>
    <ApCallout v-else-if="noEarlier" class="mb-3" tone="caution">{{ noEarlier }}</ApCallout>
    <div v-if="decided" class="flex flex-col gap-2">
      <p data-approval-decided class="m-0 text-md text-readout">
        {{ decided }}
        <ApButton
          v-if="report"
          size="compact"
          variant="ghost"
          :aria-expanded="showReport"
          aria-controls="approval-report"
          @click="showReport = !showReport"
        >
          {{ showReport ? "Hide report" : "Show report" }}
        </ApButton>
      </p>
      <ComparisonReport v-if="report && showReport" id="approval-report" :report="report" />
    </div>
    <div v-else class="flex flex-col gap-3">
      <ApCallout v-if="report?.replay.status === 'not_run'" tone="caution">{{
        REPLAY_NOT_RUN
      }}</ApCallout>
      <ComparisonReport v-if="report" :report="report" />
      <p v-else class="m-0 text-md text-text-2">
        No comparison has been run for {{ revWord }} yet.
      </p>
      <ApprovalFacts :revision="revision" />
      <p v-if="blocked" class="m-0 text-md text-text-2">{{ blocked }}</p>
      <!-- ux U88 (A6): Approve's reason, with the way on; Reject stays. -->
      <p v-else-if="approveBlocked && revision.viewer_can_decide" class="m-0 text-md text-text-2">
        {{ approveBlocked }}
        <RouterLink
          v-if="revision.cannot_approve_because === 'not_in_catalog'"
          :to="CATALOG"
          class="text-readout underline"
          >Open the catalog</RouterLink
        >
      </p>
      <details v-if="blockCode && (blocked || approveBlocked)" class="text-sm">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ blockCode }}</p>
      </details>
      <p
        v-if="noEarlier && !blocked && !approveBlocked && revision.viewer_can_decide"
        class="m-0 text-md text-text-2"
      >
        {{ NO_EARLIER_APPROVE }}
      </p>
      <ApprovalActions
        v-if="!blocked && revision.viewer_can_decide"
        :rev-word="revWord"
        :report-id="report?.report_id ?? null"
        :busy="act.busy.value"
        :approve-blocked="approveBlocked"
        @run="act.run"
        @approve="act.approve"
        @reject="sheet?.open()"
      />
      <ApCallout v-if="panelFailure" tone="crit"
        >{{ panelFailure.text }}
        <details v-if="panelFailure.code" class="mt-1 text-sm">
          <summary class="ap-label cursor-pointer">Technical details</summary>
          <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ panelFailure.code }}</p>
        </details>
        <template v-if="panelFailure.runAgain" #action
          ><ApButton size="compact" @click="runAgain">Run comparison</ApButton></template
        >
        <template v-else-if="panelFailure.openCatalog" #action
          ><RouterLink :to="CATALOG" class="text-sm text-readout underline"
            >Open the catalog</RouterLink
          ></template
        >
      </ApCallout>
    </div>
    <RejectSheet
      ref="sheet"
      :rev="rev"
      :busy="act.busy.value === 'reject'"
      :error="act.failure.value?.from === 'reject' ? act.failure.value.text : null"
      :error-code="act.failure.value?.from === 'reject' ? (act.failure.value.code ?? null) : null"
      @reject="reject"
    />
  </ApPanel>
</template>
