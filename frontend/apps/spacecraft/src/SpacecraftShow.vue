<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import StatusBadge from "./StatusBadge.vue";

type StatusTone = "ready" | "attention" | "blocked" | "info";

type Status = {
  tone: StatusTone;
  label: string;
};

type NavigationItem = {
  label: string;
  href: string | null;
};

type NavigationLink = {
  label: string;
  href: string;
};

type Page = {
  id: string;
  header: {
    title: string;
    breadcrumbs: NavigationItem[];
    title_suffix: {
      set: boolean;
      label: string;
    };
  };
};

type ProfileBinding = {
  id: string;
  eyebrow: string;
  bound: boolean;
  title: string;
  description: string | null;
  version: string | null;
  protocols: Array<{
    label: string;
    value: string;
  }>;
  status: Status;
  view_profile_href: string | null;
  profile_action: NavigationLink;
};

type ApplicationRow = {
  id: string;
  application_key: string;
  display_name: string;
  status: Status;
  manage_href: string | null;
};

type ApplicationInventory = {
  id: string;
  list_id: string;
  visible: boolean;
  title: string;
  description: string;
  empty: boolean;
  empty_state: string;
  rows: ApplicationRow[];
  view_action: NavigationLink;
};

type WorkflowCard = {
  id: string;
  title: string;
  value: string;
  description: string;
  status: Status;
  action: NavigationLink;
};

type DetailValue = {
  label: string;
  value: string;
};

type Overview = {
  title: string;
  scid: DetailValue;
  display_name: DetailValue;
  spacecraft_id: DetailValue;
  mission: DetailValue & { href: string };
  organization_id: DetailValue;
  metadata_json: string | null;
};

defineProps<{
  page: Page;
  profile_binding: ProfileBinding;
  applications: ApplicationInventory;
  workflow_cards: WorkflowCard[];
  overview: Overview;
}>();
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadencePageHeading :breadcrumbs="page.header.breadcrumbs">
      <template #title>{{ page.header.title }} </template>
      <template #metadata
        ><span>
          <span v-if="page.header.title_suffix.set" class="mc-value-small text-base-content">{{
            page.header.title_suffix.label
          }}</span>
          <span v-else class="hud-label text-warning/70">
            {{ page.header.title_suffix.label }}
          </span>
        </span></template
      >
    </CadencePageHeading>

    <CadenceCard
      :id="profile_binding.id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-2">
          <p class="hud-label">{{ profile_binding.eyebrow }}</p>
          <template v-if="profile_binding.bound">
            <div class="flex items-baseline gap-3">
              <h2 class="text-lg font-semibold">{{ profile_binding.title }}</h2>
              <span class="mc-value-small text-base-content">
                {{ profile_binding.version }}
              </span>
            </div>
            <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
              <template
                v-for="(protocol, index) in profile_binding.protocols"
                :key="protocol.label"
              >
                <span class="hud-label">{{ protocol.label }}</span>
                <span class="font-mono uppercase text-primary/80">
                  {{ protocol.value }}
                </span>
                <span
                  v-if="index < profile_binding.protocols.length - 1"
                  class="text-base-content/30"
                  >·</span
                >
              </template>
            </div>
          </template>
          <template v-else>
            <h2 class="text-lg font-semibold text-base-content/70">
              {{ profile_binding.title }}
            </h2>
            <p class="text-sm text-base-content/70">
              {{ profile_binding.description }}
            </p>
          </template>
        </div>
        <StatusBadge :status="profile_binding.status.tone" :label="profile_binding.status.label" />
      </div>

      <div class="mt-5 flex gap-4 text-sm border-t border-base-300/50 pt-4">
        <a
          v-if="profile_binding.view_profile_href"
          :href="profile_binding.view_profile_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="text-primary hover:underline"
          >View profile →</a
        >
        <a
          :href="profile_binding.profile_action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="text-primary hover:underline"
          >{{ profile_binding.profile_action.label }}</a
        >
      </div>
    </CadenceCard>

    <CadenceCard
      v-if="applications.visible"
      :id="applications.id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <p class="hud-label">{{ applications.title }}</p>
      <div class="mt-3 space-y-3">
        <p class="text-sm text-base-content/70">{{ applications.description }}</p>
        <p v-if="applications.empty" class="text-sm text-base-content/60">
          {{ applications.empty_state }}
        </p>
        <div v-else :id="applications.list_id" class="grid gap-3 md:grid-cols-2">
          <div
            v-for="application in applications.rows"
            :id="application.id"
            :key="application.application_key"
            class="rounded border border-base-300 bg-base-100/40 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="font-medium">{{ application.display_name }}</p>
              <a
                v-if="application.manage_href"
                :href="application.manage_href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-xs text-primary hover:underline"
                >Manage</a
              >
            </div>
            <div class="mt-2">
              <StatusBadge :status="application.status.tone" :label="application.status.label" />
            </div>
          </div>
        </div>
        <a
          :href="applications.view_action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="mt-3 inline-flex text-sm text-primary hover:underline"
          >{{ applications.view_action.label }} →</a
        >
      </div>
    </CadenceCard>

    <section id="spacecraft-interpretation-overview" class="grid gap-4 xl:grid-cols-3">
      <CadenceCard
        v-for="card in workflow_cards"
        :id="card.id"
        :key="card.id"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <div class="flex items-start justify-between gap-3">
          <p class="hud-label">{{ card.title }}</p>
          <StatusBadge :status="card.status.tone" :label="card.status.label" />
        </div>
        <h2 class="mt-3 text-base font-semibold">{{ card.value }}</h2>
        <p class="mt-2 text-sm text-base-content/70">{{ card.description }}</p>
        <a
          :href="card.action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="mt-4 inline-flex text-sm text-primary hover:underline"
          >{{ card.action.label }} →</a
        >
      </CadenceCard>
    </section>

    <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
      <p class="hud-label">{{ overview.title }}</p>
      <div class="mt-3 grid gap-x-8 gap-y-1 md:grid-cols-2">
        <CadenceDataRow
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="overview.scid.label"
        >
          <span class="hud-data-value">{{ overview.scid.value }}</span>
        </CadenceDataRow>
        <CadenceDataRow
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="overview.display_name.label"
        >
          <span class="hud-data-value">{{ overview.display_name.value }}</span>
        </CadenceDataRow>
        <CadenceDataRow
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="overview.spacecraft_id.label"
        >
          <span class="hud-data-value">
            <span class="text-xs">{{ overview.spacecraft_id.value }}</span>
          </span>
        </CadenceDataRow>
        <CadenceDataRow
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="overview.mission.label"
        >
          <a
            :href="overview.mission.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="hud-data-value text-primary hover:underline"
            >{{ overview.mission.value }}</a
          >
        </CadenceDataRow>
        <CadenceDataRow
          row-class="hud-data-row md:col-span-2"
          label-class="hud-data-label"
          :label="overview.organization_id.label"
        >
          <span class="hud-data-value text-xs">{{ overview.organization_id.value }}</span>
        </CadenceDataRow>
      </div>

      <div v-if="overview.metadata_json !== null" class="pt-2">
        <CadenceDetailsFrame class="text-sm">
          <summary class="cursor-pointer hud-label hover:text-primary">Metadata</summary>
          <pre
            class="mt-2 p-3 bg-base-300/40 border border-base-300 rounded-sm overflow-x-auto text-xs font-mono"
            >{{ overview.metadata_json }}</pre>
        </CadenceDetailsFrame>
      </div>
    </CadenceCard>
  </div>
</template>
