<script setup lang="ts">
defineOptions({ inheritAttrs: false });
defineProps<{ id: string; title: string; href: string | null }>();
</script>
<template>
  <section :id="id" class="p-6">
    <h1 class="text-xl font-semibold">{{ title }}</h1>
    <p class="mt-3 text-sm">
      Open this page in the Cadence Ops workspace with your current permissions.
    </p>
    <a v-if="href" :id="`${id}-open`" class="btn btn-primary mt-4" :href="href"
      >Open in workspace</a
    >
    <p v-else role="status" class="mt-3 text-sm">The requested page identity is unavailable.</p>
  </section>
</template>
