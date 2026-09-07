<script setup lang="ts">
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
defineProps<{ page: { csrf_token: string } }>();
</script>
<template>
  <section class="space-y-4">
    <header class="text-center">
      <h1 class="text-xl font-bold">Enter admin mode</h1>
      <p class="mt-1 text-xs text-base-content/70">
        Re-enter your password to temporarily enable platform-wide administration.
      </p>
    </header>
    <form id="admin-mode-form" action="/admin-mode" method="post" class="space-y-4">
      <input type="hidden" name="_csrf_token" :value="page.csrf_token" />
      <CadenceField label="Password" control-id="admin_mode_password"
        ><input
          id="admin_mode_password"
          name="admin_mode[password]"
          type="password"
          autocomplete="current-password"
          required
          class="w-full input"
      /></CadenceField>
      <CadenceButton type="submit" variant="primary" class="w-full">Enter admin mode</CadenceButton>
    </form>
  </section>
</template>
