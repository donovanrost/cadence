<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton } from "@/ui";

/**
 * U78 id cells: mono, middle-truncated (the prefix and the distinguishing tail stay readable), the
 * whole id in the title and to screen readers, and a copy button. '—' when there's none.
 */
const props = defineProps<{ id: string | null | undefined; label: string }>();
const KEEP = 8;
const short = computed(() => {
  const id = props.id;
  if (!id || id.length <= KEEP * 2 + 1) return id ?? null;
  return `${id.slice(0, KEEP)}…${id.slice(-KEEP)}`;
});
const copied = ref<string | null>(null);
/** a11y B6 (#243): a copy that failed is an alert; one that worked, a status. */
const copyFailed = ref(false);
async function copy() {
  if (!props.id) return;
  try {
    await navigator.clipboard.writeText(props.id);
    copied.value = "Copied.";
    copyFailed.value = false;
  } catch {
    copied.value = "Couldn't copy.";
    copyFailed.value = true;
  }
}
</script>

<template>
  <span v-if="!id" class="text-text-4">—</span>
  <span v-else class="inline-flex items-center gap-1">
    <span :title="id" class="whitespace-nowrap" aria-hidden="true">{{ short }}</span>
    <span class="sr-only">{{ id }}</span>
    <ApButton size="compact" variant="ghost" :aria-label="`Copy ${label}`" @click="copy"
      >⧉</ApButton
    >
    <span role="status" class="sr-only">{{ copyFailed ? "" : copied }}</span>
    <span role="alert" class="sr-only">{{ copyFailed ? copied : "" }}</span>
  </span>
</template>
