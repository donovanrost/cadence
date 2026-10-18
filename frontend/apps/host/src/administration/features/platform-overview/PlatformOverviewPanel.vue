<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import type { PlatformOverview } from "./contracts";
defineProps<{ model: PlatformOverview }>();
useManagementHeader("/admin", { description: "Organizations and system diagnostics" });
</script>
<template>
  <div id="admin-home" class="space-y-6">
    <div class="grid gap-4 md:grid-cols-3">
      <CadenceCard
        id="admin-home-organizations-card"
        class="card bg-base-200 border border-base-300"
        body-class="p-6"
      >
        <h2 class="hud-label">Organizations</h2>
        <p class="mt-2 text-3xl font-bold font-mono">{{ model.counts.organizations }}</p>
        <a
          id="admin-home-organizations-link"
          href="/admin/organizations"
          class="btn btn-primary btn-sm mt-4"
          >Manage organizations</a
        >
      </CadenceCard>
      <CadenceCard
        id="admin-home-users-card"
        class="card bg-base-200 border border-base-300"
        body-class="p-6"
      >
        <h2 class="hud-label">Active users</h2>
        <p class="mt-2 text-3xl font-bold font-mono">{{ model.counts.active_users }}</p>
        <p class="mt-4 text-sm text-base-content/70">Active accounts across the platform.</p>
      </CadenceCard>
      <CadenceCard
        id="admin-home-runtime-card"
        class="card bg-base-200 border border-base-300"
        body-class="p-6"
      >
        <h2 class="hud-label">Runtime</h2>
        <p class="mt-2 text-sm text-base-content/70">
          Inspect runtime diagnostics and dashboard decisions.
        </p>
        <a id="admin-home-runtime-link" href="/admin/runtime" class="btn btn-sm mt-4"
          >View runtime</a
        >
      </CadenceCard>
    </div>
    <a
      id="admin-home-create-organization"
      href="/admin/organizations/new"
      class="btn btn-primary btn-sm"
      >Create organization</a
    >
  </div>
</template>
