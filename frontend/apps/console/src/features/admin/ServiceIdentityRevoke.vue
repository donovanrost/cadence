<script setup lang="ts">
import { ref } from "vue";
import { ApButton } from "@/ui";

/** Revoke (Admin.md): danger, confirms "Revoke pipeline-ingest? Anything using its token stops working now." */
defineProps<{ name: string }>();
defineEmits<{ revoke: [] }>();
const confirming = ref(false);
</script>

<template>
  <ApButton v-if="!confirming" size="compact" variant="ghost" @click="confirming = true"
    >Revoke…</ApButton
  >
  <span v-else class="inline-flex items-center gap-2">
    <span class="text-sm text-text-2"
      >Revoke {{ name }}? Anything using its token stops working now.</span
    >
    <ApButton size="compact" variant="danger" @click="$emit('revoke')">Revoke</ApButton>
    <ApButton size="compact" variant="ghost" @click="confirming = false">Keep</ApButton>
  </span>
</template>
