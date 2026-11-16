<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { RouterView, useRoute, useRouter } from "vue-router";
import { startSocket } from "@/live/socket.ts";
import AppShell from "@/shell/AppShell.vue";
import BootScreen from "@/shell/BootScreen.vue";
import { useBootstrap } from "@/shell/bootstrap.ts";
import SessionProvider from "@/shell/SessionProvider.vue";
import PaletteRoot from "@/features/palette/PaletteRoot.vue";
import { ConfigStatus, StagedBar } from "@/features/changes/index.ts";
import { FleetPosture } from "@/features/fleet/index.ts";
import AuthLayout from "@/features/auth/AuthLayout.vue";

/**
 * L5 (lead): wait for the first route, then either the public AuthLayout (sign-in, invitation,
 * no-organization; no session needed) or the bootstrapped console. A signed-in session with no
 * organizations goes to auth.no-org.
 */
const route = useRoute();
const router = useRouter();
const routed = ref(false);
const isPublic = computed(() => route.meta.public === true);
const { state, load } = useBootstrap();
onMounted(async () => {
  await router.isReady();
  routed.value = true;
  if (!isPublic.value) void load();
});
// Leaving a public route inside the SPA (e.g. a link to home) needs the session then.
watch(isPublic, (pub) => {
  if (routed.value && !pub && state.value.status === "loading") void load();
});

watch(state, (current) => {
  if (current.status !== "ready") return;
  if (current.session.organizations.length === 0) {
    void router.replace({ name: "auth.no-org" });
    return;
  }
  startSocket(current.session.socket.path, current.session.csrf_token);
});
</script>

<template>
  <BootScreen v-if="!routed" />
  <AuthLayout v-else-if="isPublic"><RouterView /></AuthLayout>
  <BootScreen v-else-if="state.status === 'loading'" />
  <BootScreen v-else-if="state.status === 'failed'" :error="state.error" @retry="load" />
  <SessionProvider v-else :session="state.session">
    <AppShell>
      <!-- Fleet posture, both modes at mission scope (ux IA §Top bar; replaces the context rail). -->
      <template #topbar-status><FleetPosture /></template>
      <!-- fe-setup: CONFIG rN · n STAGED (renders nothing until the mission has change sets). -->
      <template #topbar-setup-status><ConfigStatus /></template>
      <!-- fe-setup: staged bar under Setup screens (hidden while nothing is staged). -->
      <template #setup-footer><StagedBar /></template>
    </AppShell>
    <PaletteRoot />
  </SessionProvider>
</template>
