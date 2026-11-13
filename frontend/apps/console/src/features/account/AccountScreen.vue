<script setup lang="ts">
import { roleText } from "@/api";
import { computed, ref } from "vue";
import { useSession } from "@/shell/index.ts";
import { ApKeyValue, ApPageHeader, ApPanel, ApTable, type ApColumn } from "@/ui";
import InvitationsPanel from "./InvitationsPanel.vue";
import PasswordPanel from "./PasswordPanel.vue";
import SessionsPanel from "./SessionsPanel.vue";

/** Your account: profile and organizations (session bootstrap), password, sessions (api Account). */
const sessions = ref<InstanceType<typeof SessionsPanel> | null>(null);
const session = useSession();

const profile = computed(() => [
  { key: "name", label: "Name", value: session.user.display_name ?? "Not set" },
  { key: "email", label: "Email", value: session.user.email, mono: true },
  { key: "admin", label: "Platform admin mode", value: session.admin_mode ? "On" : "Off" },
]);

type Membership = Readonly<{ id: string; name: string; role: string; missions: string }>;
const memberships = computed<Membership[]>(() =>
  session.organizations.map((org) => ({
    id: org.id,
    name: org.name,
    role: org.role === null ? "—" : roleText(org.role),
    missions: org.missions.length === 0 ? "None" : org.missions.map((m) => m.name).join(", "),
  })),
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Organization" },
  { key: "role", label: "Role" },
  { key: "missions", label: "Missions you can open" },
];
</script>

<template>
  <div class="flex max-w-[1100px] flex-col gap-4">
    <ApPageHeader label="Cadence · account" title="Your account" size="reading" />
    <InvitationsPanel />
    <ApPanel index="A1" title="Profile">
      <ApKeyValue :items="profile" :columns="2" />
    </ApPanel>
    <ApPanel index="A2" title="Organizations" :meta="`${memberships.length} total`" flush>
      <ApTable
        :columns="columns"
        :rows="memberships"
        :row-key="(row) => row.id"
        caption="Your organizations"
      />
    </ApPanel>
    <div class="grid grid-cols-1 gap-4 console:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
      <PasswordPanel @changed="sessions?.refetch()" />
      <SessionsPanel ref="sessions" />
    </div>
  </div>
</template>
