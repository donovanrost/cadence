<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import AdminOverview from "./admin/AdminOverview.vue";
import AdminShell from "./admin/AdminShell.vue";
import OrganizationsView from "./admin/OrganizationsView.vue";
import RuntimeView from "./admin/RuntimeView.vue";
import ApplicationWorkspace from "./ApplicationWorkspace.vue";
import type { FrontendSession, SignInCredentials } from "./auth/auth-client";
import { currentSession, signIn, signOut } from "./auth/auth-client";
import SignInView from "./auth/SignInView.vue";

const route = ref(window.location.pathname);
const session = shallowRef<FrontendSession>();
const checkingSession = ref(true);
const signingIn = ref(false);
const signInError = ref<string>();

onMounted(async () => {
  window.addEventListener("popstate", syncRoute);
  try {
    session.value = await currentSession();
  } catch (reason) {
    signInError.value = messageFor(reason, "The session boundary could not be reached.");
  } finally {
    checkingSession.value = false;
    settleRoute();
  }
});

onBeforeUnmount(() => window.removeEventListener("popstate", syncRoute));

async function authenticate(credentials: SignInCredentials): Promise<void> {
  signingIn.value = true;
  signInError.value = undefined;
  try {
    session.value = await signIn(credentials);
    navigate("/admin", true);
  } catch (reason) {
    signInError.value = messageFor(reason, "The supplied credentials were rejected.");
  } finally {
    signingIn.value = false;
  }
}

async function endSession(): Promise<void> {
  try {
    await signOut();
  } finally {
    session.value = undefined;
    signInError.value = undefined;
    navigate("/sign-in", true);
  }
}

function navigate(path: string, replace = false): void {
  const method = replace ? "replaceState" : "pushState";
  window.history[method]({}, "", path);
  route.value = path;
  settleRoute();
}

function syncRoute(): void {
  route.value = window.location.pathname;
  settleRoute();
}

function settleRoute(): void {
  if (checkingSession.value) return;
  if (!session.value) {
    if (route.value !== "/sign-in") navigate("/sign-in", true);
    return;
  }

  if (route.value === "/" || route.value === "/sign-in") {
    navigate("/admin", true);
    return;
  }

  if (!allowedRoute(route.value)) navigate("/admin", true);
}

function allowedRoute(path: string): boolean {
  return ["/admin", "/admin/organizations", "/admin/runtime", "/applications"].includes(path);
}

function messageFor(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}
</script>

<template>
  <div v-if="checkingSession" id="session-check" class="session-check" role="status">
    <span>CD / SESSION</span>
    <strong>Resolving authority boundary</strong>
  </div>

  <SignInView
    v-else-if="!session"
    :error="signInError"
    :loading="signingIn"
    @submit="authenticate"
  />

  <ApplicationWorkspace v-else-if="route === '/applications'" @navigate="navigate" />

  <AdminShell
    v-else
    :active-route="route"
    :session="session"
    @navigate="navigate"
    @sign-out="endSession"
  >
    <OrganizationsView v-if="route === '/admin/organizations'" />
    <RuntimeView v-else-if="route === '/admin/runtime'" :session="session" />
    <AdminOverview v-else @navigate="navigate" />
  </AdminShell>
</template>

<style scoped>
.session-check {
  min-height: 100vh;
  display: grid;
  place-content: center;
  gap: var(--cadence-space-3);
  color: var(--cadence-color-text);
  background: var(--cadence-color-canvas);
  text-align: center;
}

.session-check span {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.session-check strong {
  font-size: var(--cadence-type-title-md);
  font-weight: 580;
}
</style>
