<script setup lang="ts">
import { ref } from "vue";
import { ApButton } from "@/ui";

/**
 * People.md U3: the new API token, shown once in a well with Copy (O6: the server keeps only a
 * digest). Held in this component's state only, never in the URL or storage.
 */
defineProps<{ token: string }>();
const copied = ref<"yes" | "failed" | null>(null);
async function copy(token: string) {
  try {
    await navigator.clipboard.writeText(token);
    copied.value = "yes";
  } catch {
    copied.value = "failed";
  }
}
</script>

<template>
  <div class="flex flex-col gap-2 border border-line bg-raised p-4">
    <span class="ap-label">API token</span>
    <code class="font-mono text-sm break-all text-readout select-all">{{ token }}</code>
    <div class="flex flex-wrap items-center gap-3">
      <ApButton size="compact" @click="copy(token)">{{
        copied === "yes" ? "Copied" : "Copy"
      }}</ApButton>
      <span v-if="copied === 'yes'" class="text-sm text-nominal-text" role="status">Copied.</span>
      <span v-else-if="copied === 'failed'" class="text-sm text-caution-text" role="status"
        >Couldn't copy; select the token and copy it by hand.</span
      >
    </div>
    <p class="m-0 text-sm text-text-2">You won't see this again.</p>
  </div>
</template>
