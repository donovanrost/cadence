<script setup lang="ts">
import { computed } from "vue";
import { readPage } from "./contracts";
const props = defineProps<{ page: unknown }>();
const model = computed(() => readPage(props.page));
</script>
<template>
  <section v-if="model" class="space-y-4 text-center">
    <h1 class="text-xl font-bold">No organization access</h1>
    <p class="text-sm text-base-content/70">
      You don't have access to any organization yet. Ask an administrator for an invitation.
    </p>
    <div
      v-if="model.pending_invitations_count"
      class="p-4 border border-primary/30 rounded-sm bg-primary/5 text-left"
    >
      <p class="text-sm">
        You have <strong class="text-primary">{{ model.pending_invitations_count }}</strong> pending
        {{ model.pending_invitations_count === 1 ? "invitation" : "invitations" }}.
      </p>
      <a
        href="/notifications"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="mt-2 inline-flex items-center gap-1 text-xs text-primary uppercase tracking-wide hover:underline"
        >View notifications<span class="hero-arrow-right h-3 w-3"></span
      ></a>
    </div>
    <form id="no-organization-sign-out" action="/session" method="post" class="w-full">
      <input type="hidden" name="_method" value="delete" /><input
        type="hidden"
        name="_csrf_token"
        :value="model.csrf_token"
      /><button
        type="submit"
        class="btn btn-ghost btn-sm w-full gap-2 text-xs uppercase tracking-wide"
      >
        <span class="hero-arrow-right-start-on-rectangle h-4 w-4"></span>Sign out
      </button>
    </form>
  </section>
  <p v-else id="organization-access-unavailable" role="alert" class="alert alert-warning">
    This page is unavailable. <a href="/sign-in" class="link">Return to sign in</a>.
  </p>
</template>
