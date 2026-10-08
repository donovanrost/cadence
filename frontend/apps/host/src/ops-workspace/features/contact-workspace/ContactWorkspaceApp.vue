<script setup lang="ts">
import { inject, provide, ref, markRaw, watch } from "vue";
import { RouterLink, RouterView, useRouter, useRoute } from "vue-router";
import { contactNavigationKey } from "@cadence/planning-and-contacts/contact-scheduling";
import ApplicationShell from "../../../shell/ApplicationShell.vue";
import { workspaceClientKey } from "./client";
import { workspaceBootstrapKey } from "./router";
import { workspaceBase, workspaceDestination, type WorkspaceBootstrap } from "./contracts";
import ContactWorkspaceLink from "./ContactWorkspaceLink.vue";
const props = defineProps<{ bootstrap: WorkspaceBootstrap }>();
provide(workspaceBootstrapKey, props.bootstrap);
const client = inject(workspaceClientKey);
if (!client) throw Error("Missing contact client");
const router = useRouter();
const route = useRoute();
const navigationError = ref("");
const content = ref<HTMLElement>();
const base = workspaceBase(props.bootstrap.missionId);
provide(contactNavigationKey, {
  link: markRaw(ContactWorkspaceLink),
  navigate(href) {
    const destination = workspaceDestination(
      href,
      props.bootstrap.missionId,
      window.location.origin,
    );
    if (!destination) {
      window.location.assign(href);
      return;
    }
    router.push(destination).catch(() => {
      navigationError.value = "This page could not be opened.";
    });
  },
});
watch(
  () => route.fullPath,
  () => {
    navigationError.value = "";
    document.title = `${route.name === "contact-record" ? "Contact record" : "Contact scheduling"} · Cadence`;
  },
  { immediate: true },
);
watch(
  () => route.fullPath,
  () => {
    if (content.value) content.value.scrollTop = 0;
  },
  { flush: "post" },
);
</script>
<template>
  <ApplicationShell
    :context="bootstrap.context"
    variant="ops"
    connection-label="Refreshes every 5 seconds"
    managed-page
  >
    <div id="contact-workspace" ref="content" class="flex-1 min-h-0 overflow-y-auto">
      <nav aria-label="Contact workspace" class="flex gap-4 border-b border-base-300 px-6 py-3">
        <RouterLink id="contact-workspace-home" :to="base" class="link"
          >Contact scheduling</RouterLink
        >
        <a :href="`/missions/${encodeURIComponent(bootstrap.missionId)}/ops`" class="link"
          >Operations overview</a
        >
      </nav>
      <p v-if="navigationError" role="alert" class="p-6">{{ navigationError }}</p>
      <div
        v-if="client.sessionChanged.value"
        id="contact-workspace-session-changed"
        role="alert"
        class="p-6"
      >
        <p>Your session changed. Reload to continue with your current account and organization.</p>
        <a :href="base" class="link">Reload contact workspace</a>
      </div>
      <RouterView v-else v-slot="{ Component, route: currentRoute }">
        <component :is="Component" :key="currentRoute.fullPath" />
      </RouterView>
    </div>
  </ApplicationShell>
</template>
