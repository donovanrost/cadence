<script setup lang="ts">
defineProps<{ page: { csrf_token: string; pending_invitations_count: number } }>();
</script>
<template>
  <section class="space-y-4 text-center">
    <h1 class="text-xl font-bold">No organization access</h1>
    <p class="text-sm text-base-content/70">
      You don't have access to any organization yet. Ask an administrator for an invitation.
    </p>
    <div
      v-if="page.pending_invitations_count"
      class="p-4 border border-primary/30 rounded-sm bg-primary/5 text-left"
    >
      <p class="text-sm">
        You have <strong class="text-primary">{{ page.pending_invitations_count }}</strong> pending
        {{ page.pending_invitations_count === 1 ? "invitation" : "invitations" }}.
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
        :value="page.csrf_token"
      /><button
        type="submit"
        class="btn btn-ghost btn-sm w-full gap-2 text-xs uppercase tracking-wide"
      >
        <span class="hero-arrow-right-start-on-rectangle h-4 w-4"></span>Sign out
      </button>
    </form>
  </section>
</template>
