<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import { failureOutcome } from "./actions.ts";
import { rebaseOp, type RebaseChoice } from "./rebase.ts";

/**
 * Changes.md K1: a staged change whose fields live moved under (Conflicts check). Keep mine
 * re-applies it on the live revision; Take live drops the edit for the conflicting fields.
 */
const props = defineProps<{ missionId: string; opIds: readonly string[]; canAct: boolean }>();
const emit = defineEmits<{ done: [] }>();
const busy = ref(false);
const failure = ref<string | null>(null);

async function choose(choice: RebaseChoice) {
  busy.value = true;
  failure.value = null;
  try {
    for (const id of props.opIds) {
      const r = await rebaseOp(props.missionId, id, choice);
      if (!r.ok) {
        failure.value = failureOutcome(r.error, "changed").sentence;
        break;
      }
    }
  } finally {
    busy.value = false;
    emit("done");
  }
}
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-3 border-t border-hairline-faint bg-vacuum px-4 py-2.5"
  >
    <span class="text-sm text-caution-text"
      >Live changed under this since it was staged (see Conflicts).</span
    >
    <template v-if="canAct">
      <ApButton
        size="compact"
        :disabled="busy"
        disabled-reason="Working…"
        @click="choose('keep_mine')"
        >Keep mine</ApButton
      >
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="busy"
        disabled-reason="Working…"
        @click="choose('take_live')"
        >Take live</ApButton
      >
    </template>
    <ApCallout v-if="failure" tone="crit" class="w-full">{{ failure }}</ApCallout>
  </div>
</template>
