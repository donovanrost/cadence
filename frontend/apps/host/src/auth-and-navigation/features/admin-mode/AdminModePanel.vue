<script setup lang="ts">
import { computed } from "vue";
import { readPage } from "./contracts";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
const props = defineProps<{ page: unknown }>();
const model = computed(() => readPage(props.page));
</script>
<template>
  <section v-if="model" class="space-y-4">
    <header class="text-center">
      <h1 class="text-xl font-bold">Enter admin mode</h1>
      <p class="mt-1 text-xs text-base-content/70">
        Re-enter your password to temporarily enable platform-wide administration.
      </p>
    </header>
    <form id="admin-mode-form" action="/admin-mode" method="post" class="space-y-4">
      <input type="hidden" name="_csrf_token" :value="model.csrf_token" />
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
  <p v-else id="admin-mode-unavailable" role="alert" class="alert alert-warning">
    This page is unavailable. <a href="/sign-in" class="link">Return to sign in</a>.
  </p>
</template>
