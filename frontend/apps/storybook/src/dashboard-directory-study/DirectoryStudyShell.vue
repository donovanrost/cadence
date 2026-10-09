<script setup lang="ts">
import { onBeforeUnmount, onMounted } from "vue";
import ApplicationShell from "../../../host/src/shell/ApplicationShell.vue";
import HostPage from "../../../host/src/shell/HostPage.vue";
import DashboardDirectoryStudy from "./DashboardDirectoryStudy.vue";
import { missionPath, type Scenario } from "./fixtures";
import { useDirectoryStudy, type Presentation, type QuickAccess } from "./state";

const props = withDefaults(
  defineProps<{
    initial?: Scenario;
    quickAccess?: QuickAccess;
    presentation?: Presentation;
    teammateAfterMs?: number;
  }>(),
  { initial: "established", quickAccess: "refined", presentation: "list" },
);
const study = useDirectoryStudy(props.initial);
const breadcrumbs = [
  { label: "Flight Operations", href: "/" },
  { label: "Kestrel", href: missionPath },
];
const context = {
  version: 1,
  user: { user_id: "engineer", display_name: "Mission engineer", email: "engineer@example.test" },
  organization: { organization_id: "flight", display_name: "Flight Operations" },
  organizations: [],
  capabilities: [],
  platform_admin: false,
  admin_mode: false,
  csrf_token: "storybook-csrf",
  notifications: [],
  unread_count: 0,
  nav_context: "mission",
  nav_item: "ops_dashboards",
  mission: { mission_id: "kestrel", display_name: "Kestrel", slug: "kestrel" },
};

let timer: ReturnType<typeof setTimeout> | undefined;
onMounted(() => {
  if (props.teammateAfterMs !== undefined)
    timer = setTimeout(study.actions.teammateSaves, props.teammateAfterMs);
});
onBeforeUnmount(() => clearTimeout(timer));

// Links stay real anchors; the study reports where they would go instead of leaving.
function intercept(event: MouseEvent) {
  const anchor = event.target instanceof Element ? event.target.closest("a") : null;
  const href = anchor?.getAttribute("href");
  if (!href?.startsWith("/") || href.startsWith("/iframe.html")) return;
  event.preventDefault();
  study.visit(href);
}
</script>

<template>
  <div @click="intercept">
    <ApplicationShell class="h-dvh" variant="mission_sidebar" :context="context" managed-page>
      <HostPage title="Dashboards" :breadcrumbs="breadcrumbs">
        <DashboardDirectoryStudy
          :study="study"
          :quick-access="quickAccess"
          :presentation="presentation"
        />
      </HostPage>
    </ApplicationShell>
  </div>
</template>
