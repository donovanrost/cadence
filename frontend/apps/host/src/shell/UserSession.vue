<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";

defineProps<{ csrfToken: string }>();
</script>

<template>
  <div id="user-session-page" class="space-y-4">
    <div class="text-center">
      <p class="text-primary tracking-[0.15em] text-sm font-semibold">◆ CADENCE</p>
      <h1 class="mt-2 text-xl font-semibold">Sign in</h1>
      <p class="mt-2 text-sm text-base-content/60">
        Enter your operator credentials to access the control plane.
      </p>
    </div>
    <form id="sign-in-form" action="/sign-in" method="post" class="space-y-4">
      <input type="hidden" name="_csrf_token" :value="csrfToken" />
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
</template>
