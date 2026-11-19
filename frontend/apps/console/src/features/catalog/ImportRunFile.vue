<script setup lang="ts">
/** L18: the run's stored file: its page and a plain Download link (the session cookie is enough). */
defineProps<{ artifact: Readonly<{ id: string; download_url: string }> }>();
</script>

<template>
  ·
  <RouterLink
    :to="{ name: 'setup.catalog.artifact', params: { artifactId: artifact.id } }"
    class="text-primary no-underline hover:underline"
    >Source file</RouterLink
  >
  ·
  <a :href="artifact.download_url" class="text-primary no-underline hover:underline">Download</a>
</template>
