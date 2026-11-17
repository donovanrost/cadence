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
import { cannotApproveLine, cannotDecideLine, decidedLine, REPLAY_NOT_RUN } from "./words.ts";

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
const meta = computed(() =>
  report.value?.against ? `AGAINST REV ${report.value.against.catalog_revision_number}` : undefined,
);
const decided = computed(() => decidedLine(props.revision));
const blocked = computed(() => cannotDecideLine(props.revision));
const approveBlocked = computed(() => cannotApproveLine(props.revision));
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
        <RouterLink :to="CATALOG" class="text-readout underline">Open the catalog</RouterLink>
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
      @reject="reject"
    />
  </ApPanel>
</template>
