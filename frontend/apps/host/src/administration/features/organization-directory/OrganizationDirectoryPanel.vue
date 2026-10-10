<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import { organizationHref } from "../../shared/platform-contract";
import { directoryHref, type OrganizationDirectory } from "./contracts";
defineProps<{ model: OrganizationDirectory }>();
useManagementHeader("/admin/organizations", {
  description: "Browse organizations across the platform.",
  primary: {
    id: "admin-organizations-create",
    label: "Create organization",
    icon: "hero-plus",
    href: href("/admin/organizations/new"),
  },
});
</script>
<template>
  <div id="admin-organizations-page" class="space-y-6">
    <section
      id="admin-organization-list-component"
      class="card border border-base-300 bg-base-200 p-6"
    >
      <p
        v-if="!model.organizations.length"
        id="admin-organizations-empty"
        class="py-6 text-base-content/70"
      >
        No organizations on this page.
      </p>
      <ul v-else class="divide-y divide-base-300">
        <li
          v-for="org in model.organizations"
          :id="`admin-organization-${org.id}`"
          :key="org.id"
          class="py-4"
        >
          <a :href="organizationHref(org.id)" class="link font-semibold break-words">{{
            org.name
          }}</a>
          <p class="mt-1 font-mono text-sm text-base-content/70 break-all">{{ org.slug }}</p>
        </li>
      </ul>
    </section>
    <nav aria-label="Organization pages" class="flex flex-wrap gap-3 items-center">
      <a
        v-if="model.query.after_id"
        id="admin-organizations-first"
        :href="directoryHref()"
        class="btn btn-sm"
        >First page</a
      >
      <a
        v-if="model.next_cursor"
        id="admin-organizations-next"
        :href="directoryHref(model.next_cursor)"
        class="btn btn-sm"
        >Next organizations</a
      >
      <span class="text-sm text-base-content/60"
        >{{ model.organizations.length }} organizations on this page</span
      >
    </nav>
  </div>
</template>
