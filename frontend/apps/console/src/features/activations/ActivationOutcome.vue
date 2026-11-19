<script setup lang="ts">
import { RecordLine } from "@/features/changes/index.ts";
import { decisionLine, replacedBy, type ActivationRequest } from "./api.ts";

/** Under the facts: who decided and why, or the newer request that replaced this one (lead 11-13). */
defineProps<{ request: ActivationRequest }>();
</script>

<template>
  <p v-if="decisionLine(request)" class="m-0 mt-3 text-sm text-text-2">
    <RecordLine :parts="decisionLine(request) ?? []" />
  </p>
  <p v-if="replacedBy(request)" class="m-0 mt-3 text-sm text-text-2">
    Replaced by a
    <RouterLink
      :to="{ name: 'setup.activation', params: { requestId: replacedBy(request) ?? '' } }"
      class="text-primary hover:underline"
      >newer request</RouterLink
    >.
  </p>
</template>
