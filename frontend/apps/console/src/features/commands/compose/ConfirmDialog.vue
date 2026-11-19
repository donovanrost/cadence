<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSheet } from "@/ui";

/**
 * The console's confirm pattern on the kit ApSheet: a modal question with a danger action and a
 * way back. `ask()` resolves true for the action, false for cancel, Escape or a backdrop close.
 */
defineProps<{ question: string; body?: string | undefined; confirm: string; cancel: string }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
let settle: ((ok: boolean) => void) | null = null;

function ask(): Promise<boolean> {
  settle?.(false);
  sheet.value?.open();
  return new Promise((resolve) => (settle = resolve));
}
function answer(ok: boolean) {
  const s = settle;
  settle = null;
  sheet.value?.close();
  s?.(ok);
}
defineExpose({ ask });
</script>

<template>
  <ApSheet ref="sheet" :title="question" @closed="answer(false)">
    <p v-if="body" class="m-0 text-text-2">{{ body }}</p>
    <template #footer>
      <ApButton variant="ghost" @click="answer(false)">{{ cancel }}</ApButton>
      <ApButton variant="danger" @click="answer(true)">{{ confirm }}</ApButton>
    </template>
  </ApSheet>
</template>
