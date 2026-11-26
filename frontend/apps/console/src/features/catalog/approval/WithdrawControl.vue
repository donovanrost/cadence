<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { ApButton, OutcomeCallout } from "@/ui";
import { useSession } from "@/shell";
import { withdrawRevision, type ModelKey, type ModelRevision } from "./api.ts";
import { withdrawFailure, withdrawnLine, type WithdrawFailure } from "./withdraw-words.ts";
import WithdrawSheet from "./WithdrawSheet.vue";
import { compositionInSentence, isComposed } from "../composition.ts";

/**
 * E2 (#546; U109 in #615): `Withdraw approval…` on an approved revision when the read's
 * `viewer_can_withdraw` is true, its sheet, and after it the status "Approval withdrawn. …"
 * (B6, said once). One operation id per request (this revision with this reason): a retry replays.
 */
const props = defineProps<{ revision: ModelRevision; modelKey: ModelKey }>();
const emit = defineEmits<{ changed: [] }>();
const viewerId = useSession().user.id;
/** "catalog rev 4" / "composition 3" (U109) / "this catalog revision". */
const what = computed(() => {
  const r = props.revision;
  if (isComposed(r.composition)) return compositionInSentence(r.composition);
  return r.catalog_revision ? `catalog rev ${r.catalog_revision.number}` : "this catalog revision";
});
const can = computed(
  () => props.revision.viewer_can_withdraw === true && props.revision.status === "approved",
);
const sheet = ref<InstanceType<typeof WithdrawSheet> | null>(null);
const busy = ref(false);
const failure = shallowRef<WithdrawFailure | null>(null);
const done = shallowRef<Readonly<{ tone: "nominal"; text: string }> | null>(null);
let last: Readonly<{ key: string; id: string }> | null = null;
const opId = (reason: string) => {
  const key = `${props.modelKey.revisionId} ${reason}`;
  if (last?.key !== key) last = { key, id: crypto.randomUUID() };
  return last.id;
};

function open() {
  failure.value = null;
  sheet.value?.open();
}
async function withdraw(reason: string) {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const r = await withdrawRevision(props.modelKey, reason, opId(reason));
    if (r.ok) {
      done.value = { tone: "nominal", text: withdrawnLine(what.value) };
      sheet.value?.close();
      emit("changed");
    } else failure.value = withdrawFailure(r.error, what.value, viewerId);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <OutcomeCallout v-if="done" :outcome="done" />
  <template v-if="can">
    <ApButton
      size="compact"
      variant="ghost"
      class="self-start"
      :aria-label="`Withdraw approval of ${what}`"
      @click="open"
      >Withdraw approval…</ApButton
    >
    <WithdrawSheet ref="sheet" :what="what" :busy="busy" :failure="failure" @withdraw="withdraw" />
  </template>
</template>
