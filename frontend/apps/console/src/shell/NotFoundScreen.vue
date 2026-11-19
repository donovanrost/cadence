<script setup lang="ts">
import { ApButton, ApPageHeader, ApPanel } from "@/ui";

withDefaults(defineProps<{ sentence?: string }>(), {
  sentence: "Nothing lives at this address in the console. Check the link, or start from Now.",
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApPageHeader label="Cadence" title="Not found" />
    <ApPanel>
      <p class="m-0 mb-4 text-base text-text-3">{{ sentence }}</p>
      <ApButton :to="{ name: 'home' }">Go to the console home</ApButton>
    </ApPanel>
  </div>
</template>
