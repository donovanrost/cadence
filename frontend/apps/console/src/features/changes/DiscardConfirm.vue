<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApInlineConfirm } from "@/ui";
import { discardConfirm } from "./discard-words.ts";
import type { Change } from "./shapes.ts";

/**
 * K1's Discard always confirms (ux 11-16, lead's ask from qa's probe): an in-place confirm under
 * the header, danger action, focus on Cancel, counting only what the caller may discard.
 */
const props = defineProps<{
  changes: readonly Change[];
  userId: string;
  discardAny: boolean;
  busy: boolean;
}>();
const emit = defineEmits<{ discard: [] }>();
const open = ref(false);
const words = computed(() => discardConfirm(props.changes, props.userId, props.discardAny));
function confirm() {
  open.value = false;
  emit("discard");
}
</script>

<template>
  <ApInlineConfirm
    v-model:open="open"
    :action="words.action"
    :busy="busy"
    busy-reason="Discarding…"
    @confirm="confirm"
  >
    <template #trigger="{ attrs }">
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="busy"
        disabled-reason="Working…"
        v-bind="attrs"
        >{{ discardAny ? "Discard all…" : "Discard mine…" }}</ApButton
      >
    </template>
    {{ words.sentence }}
  </ApInlineConfirm>
</template>
