<script setup lang="ts">
import { describeApiError, type ApiError } from "@/api/http.ts";
import { ApButton, ApCallout } from "@/ui";

defineProps<{ error?: ApiError }>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <main class="flex h-screen flex-col items-start justify-center gap-4 px-10">
    <p class="ap-label">Cadence · ground segment operations</p>
    <h1 class="m-0 font-display text-3xl font-semibold tracking-head uppercase">
      {{ error ? "Console unavailable" : "Starting console" }}
    </h1>
    <template v-if="error">
      <ApCallout tone="crit" class="max-w-[640px]">{{ describeApiError(error) }}</ApCallout>
      <ApButton @click="$emit('retry')">Try again</ApButton>
    </template>
    <p v-else class="m-0 font-mono text-md text-text-3" role="status">Loading your session…</p>
  </main>
</template>
