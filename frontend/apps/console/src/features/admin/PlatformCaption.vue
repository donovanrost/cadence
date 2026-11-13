<script setup lang="ts">
 /** api-ops: where platform actions are recorded (Admin.md footer caption). */
</script>

<template>
  <p class="m-0 text-sm text-text-3">
    Recorded in
    <RouterLink :to="{ name: 'admin.audit' }" class="text-readout hover:underline"
      >Admin › Audit</RouterLink
    >; organization changes also appear in that organization's Audit.
  </p>
</template>
