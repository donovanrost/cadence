<script setup lang="ts">
import { computed } from "vue";
import { readPage } from "./contracts";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";

const props = defineProps<{ page: unknown }>();
const model = computed(() => readPage(props.page));
</script>

<template>
  <div v-if="model" id="user-session-page" class="space-y-4">
    <div class="text-center">
      <p class="text-primary tracking-[0.15em] text-sm font-semibold">◆ CADENCE</p>
      <h1 class="mt-2 text-xl font-semibold">Sign in</h1>
      <p class="mt-2 text-sm text-base-content/60">
        Enter your operator credentials to access the control plane.
      </p>
    </div>
    <form id="sign-in-form" action="/sign-in" method="post" class="space-y-4">
      <input type="hidden" name="_csrf_token" :value="model.csrf_token" />
      <CadenceField control-id="user_email" label="Email">
        <input
          id="user_email"
          class="input w-full"
          name="user[email]"
          type="email"
          placeholder="operator@example.com"
          autocomplete="email"
          required
          autofocus
        />
      </CadenceField>
      <CadenceField control-id="user_password" label="Password">
        <input
          id="user_password"
          class="input w-full"
          name="user[password]"
          type="password"
          placeholder="Enter your password"
          autocomplete="current-password"
          required
        />
      </CadenceField>
      <CadenceButton id="sign-in-submit" type="submit" variant="primary" class="w-full"
        >Sign In</CadenceButton
      >
    </form>
    <p class="text-center text-xs text-base-content/50">
      Need access? Contact your organization admin.
    </p>
  </div>
  <p v-else id="sign-in-unavailable" role="alert" class="alert alert-warning">
    This page is unavailable. <a href="/sign-in" class="link">Return to sign in</a>.
  </p>
</template>
