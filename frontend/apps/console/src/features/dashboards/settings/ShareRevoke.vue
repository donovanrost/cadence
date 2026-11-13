<script setup lang="ts">
import { ref } from "vue";
import { ApButton } from "@/ui";

/** A share row's Revoke: confirms first (ux). */
defineProps<{ active: boolean }>();
defineEmits<{ revoke: [] }>();
const confirming = ref(false);
</script>

<template>
  <template v-if="active">
    <ApButton v-if="!confirming" size="compact" variant="ghost" @click="confirming = true"
      >Revoke…</ApButton
    >
    <ApButton v-else size="compact" variant="danger" @click="$emit('revoke')"
      >Revoke the link</ApButton
    >
  </template>
</template>
