<script setup lang="ts">
import { computed } from "vue";
import { useSession } from "@/shell/index.ts";
import {
  ApEmptyState,
  ApKeyValue,
  ApPageHeader,
  ApPanel,
  ApTable,
  type ApColumn,
} from "@/ui/index.ts";

/** Your account: facts from the session bootstrap. Password and sessions have no API yet. */
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
    role: org.role === null ? "—" : org.role.replaceAll("_", " "),
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
    <ApPanel index="A3" title="Password and sessions" flush>
      <ApEmptyState
        state="off"
        headline="Not available in the console yet"
        sentence="Changing your password and signing out other sessions will move here. Until then, ask an organization admin."
      />
    </ApPanel>
  </div>
</template>
