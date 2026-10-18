<script setup lang="ts">
import { computed, shallowRef } from "vue";
import {
  readSettingsSnapshot,
  type SettingsContext,
  type SettingsWriteResult,
} from "@cadence/plugin-sdk/settings";
import { readApprovalValue } from "../../host/src/settings/features/governance/contracts";
import { readWorkspaceDefault } from "../../../modules/commanding/src/features/settings/contracts";
import ApplicationShell from "../../host/src/shell/ApplicationShell.vue";
import HostPage from "../../host/src/shell/HostPage.vue";
import SettingsPage from "../../host/src/settings/SettingsPage.vue";
import { createSettingsDrafts } from "../../host/src/settings/drafts";
import { settingsFixture, settingsValue } from "../../host/src/settings/fixtures.test-support";
import type { SettingsAction } from "../../host/src/settings/contracts";
const props = withDefaults(
  defineProps<{
    scope?: "organization" | "mission";
    section?: "cadence.governance" | "commanding.defaults";
    enforced?: boolean;
    canEdit?: boolean;
  }>(),
  { scope: "mission", section: "cadence.governance", enforced: false, canEdit: true },
);
const context: SettingsContext = {
  actorId: "operator-1",
  organizationId: "organization-1",
  organizationName: "Aster Mission Systems",
  ...(props.scope === "mission"
    ? ({ scope: "mission", missionId: "mission-1", missionName: "Kestrel" } as const)
    : ({ scope: "organization", missionId: null, missionName: null } as const)),
};
const drafts = createSettingsDrafts();
const initial =
  props.section === "cadence.governance"
    ? settingsValue(props.scope)
    : {
        ...settingsValue(props.scope),
        saved: props.scope === "organization" ? { shelf: "expanded" } : null,
        effective: { shelf: "expanded" },
        organization_default: { shelf: "expanded" },
      };
const value = shallowRef<unknown>({
  ...initial,
  ...(props.enforced ? { source: "enforced", allow_override: false } : {}),
});
const snapshot = computed(() => {
  const page = settingsFixture(context, props.section, value.value);
  return { ...page, data: { ...page.data, can_edit: props.canEdit } };
});
const shell = {
  version: 1,
  user: { user_id: context.actorId, display_name: "Maya Chen", email: "maya@example.test" },
  organization: { organization_id: context.organizationId, display_name: context.organizationName },
  organizations: [],
  mission:
    context.scope === "mission"
      ? { mission_id: context.missionId, display_name: context.missionName, slug: "kestrel" }
      : null,
  capabilities: [],
  platform_admin: false,
  admin_mode: false,
  csrf_token: "storybook",
  notifications: [],
  unread_count: 0,
  nav_context: context.scope,
  nav_item: "settings",
};
async function save(action: SettingsAction): Promise<SettingsWriteResult> {
  const current = readSettingsSnapshot(value.value, (input) =>
    props.section === "cadence.governance" ? readApprovalValue(input) : readWorkspaceDefault(input),
  );
  const document = action.document;
  const chosen =
    document.value === null
      ? null
      : props.section === "cadence.governance"
        ? readApprovalValue(document.value)
        : readWorkspaceDefault(document.value);
  const allowed =
    typeof document.allow_override === "boolean" ? document.allow_override : current.allowOverride;
  const next = {
    ...initial,
    token: (current.version + 1).toString(16).padStart(64, "0"),
    version: current.version + 1,
    saved: chosen,
    effective: chosen ?? current.organizationDefault,
    organization_default: context.scope === "organization" ? chosen : current.organizationDefault,
    allow_override: allowed,
    source:
      context.scope === "organization"
        ? "organization"
        : chosen === null
          ? "inherited"
          : "overridden",
  };
  value.value = next;
  return { status: "saved", revisionId: "story-revision", snapshot: next };
}
</script>
<template>
  <div class="settings-example" @submit.prevent>
    <ApplicationShell
      :variant="scope === 'mission' ? 'mission_sidebar' : 'sidebar'"
      :context="shell"
      managed-page
    >
      <HostPage
        :title="scope === 'mission' ? 'Mission settings' : 'Organization settings'"
        :breadcrumbs="[{ label: context.organizationName }]"
      >
        <SettingsPage
          :snapshot="snapshot"
          :context="context"
          :section-id="section"
          :drafts="drafts"
          :execute="save"
          :refresh="async () => {}"
          :navigating="false"
        />
      </HostPage>
    </ApplicationShell>
  </div>
</template>
<style scoped>
.settings-example :deep(.drawer) {
  min-height: 100vh;
}
</style>
