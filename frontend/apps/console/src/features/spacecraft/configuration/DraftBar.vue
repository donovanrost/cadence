<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout, ApInlineConfirm } from "@/ui";
import type { SaveRefusal } from "./draft-words.ts";

/**
 * #595a (U94, mms-ux): under the tabs while the draft has unsaved edits: `Save draft` (busy
 * `Saving…`) and `Discard edits`, which confirms in place. A save refusal is U94's "Not saved: …"
 * line in the bar's place, an alert (B6), with an unworded code in Technical details (U20).
 */
const props = defineProps<{
  dirty: boolean;
  saving: boolean;
  failure: SaveRefusal | null;
  /** Fields that don't read as numbers: Save waits for them (A6). */
  invalid: number;
  discardQuestion: string;
}>();
const emit = defineEmits<{ save: []; discard: [] }>();
const confirming = ref(false);
const blocked = () =>
  props.saving ? "Saving…" : props.invalid > 0 ? "Correct the marked sizes first." : null;
function discard() {
  confirming.value = false;
  emit("discard");
}
</script>

<template>
  <div v-if="dirty || failure" class="flex flex-col gap-2">
    <ApCallout v-if="failure" tone="crit" role="alert">
      {{ failure.text }}
      <details v-if="failure.code" class="mt-1 text-sm">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ failure.code }}</p>
      </details>
      <!-- U94's Open profile waits for the snapshot to name the craft's profile (asked of api). -->
    </ApCallout>
    <div v-if="dirty" class="flex flex-wrap items-center gap-2" data-draft-bar>
      <ApButton
        variant="primary"
        :disabled="blocked() !== null"
        :disabled-reason="blocked() ?? undefined"
        @click="emit('save')"
        >Save draft</ApButton
      >
      <ApInlineConfirm v-model:open="confirming" action="Discard edits" @confirm="discard">
        <template #trigger="{ attrs }">
          <ApButton variant="ghost" :disabled="saving" disabled-reason="Saving…" v-bind="attrs"
            >Discard edits</ApButton
          >
        </template>
        {{ discardQuestion }}
      </ApInlineConfirm>
    </div>
  </div>
</template>
