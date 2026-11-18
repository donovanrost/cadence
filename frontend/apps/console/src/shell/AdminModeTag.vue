<script setup lang="ts">
import { ADMIN_MODE_NAME } from "@/api";
import { ApTag } from "@/ui";

/**
 * U89: the neutral ADMIN MODE tag right after an actor's name, where a decision was made in
 * platform admin mode. The caller shows it only when `admin_mode` is true.
 */
</script>

<template>
  <ApTag role="img" :aria-label="ADMIN_MODE_NAME" :title="ADMIN_MODE_NAME" label="Admin mode" />
</template>
