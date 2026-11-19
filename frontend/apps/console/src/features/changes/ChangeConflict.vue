<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import { failureOutcome } from "./actions.ts";
import { rebaseOp, type ConflictRow, type RebaseChoice } from "./rebase.ts";

/** Changes.md K1 (ux): the conflict fact beside Keep / Take, and what each choice does. */
const props = defineProps<{
  missionId: MissionId;
  opIds: readonly string[];
  row: ConflictRow;
  canAct: boolean;
}>();
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
  <div class="flex flex-col gap-2 border-t border-hairline-faint bg-vacuum px-4 py-2.5">
    <p v-for="line in row.lines" :key="line" class="m-0 text-sm text-caution-text">
      {{ line
      }}<template v-if="row.seeChecks">
        · <a href="#checks" class="text-readout hover:underline">see Conflicts</a></template
      >
    </p>
    <template v-if="canAct">
      <div class="flex flex-wrap items-center gap-3">
        <ApButton
          size="compact"
          :disabled="busy"
          disabled-reason="Working…"
          @click="choose('keep_mine')"
          >{{ row.keep }}</ApButton
        >
        <ApButton
          size="compact"
          variant="ghost"
          :disabled="busy"
          disabled-reason="Working…"
          @click="choose('take_live')"
          >{{ row.take }}</ApButton
        >
      </div>
      <p class="m-0 text-sm text-text-3">
        Keep mine: your value replaces live when applied. Take live: your change to these fields is
        dropped.
      </p>
    </template>
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
  </div>
</template>
