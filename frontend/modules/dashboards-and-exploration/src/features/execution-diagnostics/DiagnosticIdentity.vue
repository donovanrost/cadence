<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from "vue";
const props = defineProps<{ identity: string }>();
const feedback = ref("");
const pending = ref(false);
let generation = 0;
watch(
  () => props.identity,
  () => {
    generation++;
    pending.value = false;
    feedback.value = "";
  },
  { flush: "sync" },
);
onBeforeUnmount(() => {
  generation++;
});
async function copy() {
  if (pending.value) return;
  const observed = ++generation;
  pending.value = true;
  feedback.value = "";
  try {
    // An identity is opaque text, never a relative URL.
    await navigator.clipboard.writeText(props.identity);
    if (observed === generation) feedback.value = "Diagnostic identity copied.";
  } catch {
    if (observed === generation)
      feedback.value = "Copy unavailable. Select the identity field and copy it manually.";
  } finally {
    if (observed === generation) pending.value = false;
  }
}
</script>
<template>
  <div class="space-y-2">
    <label
      for="diagnostic-identity"
      class="block text-xs uppercase tracking-wide text-base-content/60"
      >Diagnostic identity</label
    >
    <div class="flex flex-wrap items-center gap-2">
      <input
        id="diagnostic-identity"
        class="input min-w-0 flex-1 font-mono text-xs"
        :value="identity"
        readonly
      />
      <button
        id="diagnostic-copy-identity"
        type="button"
        class="btn btn-sm"
        :disabled="pending"
        @click="copy"
      >
        Copy identity
      </button>
    </div>
    <p id="diagnostic-copy-feedback" role="status" class="text-xs text-base-content/70">
      {{ feedback }}
    </p>
  </div>
</template>
