<script setup lang="ts">
import { ApKeyValue, ApPanel } from "@/ui";
import type { DataSource } from "./api.ts";
import { sourceFacts } from "./present.ts";

/** S1 · what the source stores, where, and how it's doing. */
defineProps<{ source: DataSource }>();
</script>

<template>
  <ApPanel index="S1" title="Source">
    <ApKeyValue :items="sourceFacts(source)" :columns="2" />
  </ApPanel>
</template>
