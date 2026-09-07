<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { computed } from "vue";

type Page = {
  id: string;
  header: {
    eyebrow: string;
    heading: string;
    copy: string;
  };
  actions: {
    editor: {
      id: string;
      label: string;
      href: string;
      visible: boolean;
    };
    viewer: {
      id: string;
      label: string;
      href: string;
    };
  };
  versions: {
    label: string;
    count_id: string;
    count: number;
    container_id: string;
    empty_id: string;
    empty: string;
  };
  activity: {
    label: string;
    count_id: string;
    count: number;
    container_id: string;
    empty_id: string;
    empty: string;
  };
};

type DashboardVersion = {
  id: string;
  __dom_id: string;
  version: number;
  href: string;
  snapshot_kind: string;
  change_summary: string;
  saved: string;
};

type VersionAction = {
  id: string;
  label: string;
  disabled: boolean;
  payload: { version: string };
};

type SelectedVersion = {
  version: number;
  change_summary: string;
  actions: {
    visible: boolean;
    restore: VersionAction;
    publish: VersionAction;
  };
  details: Array<{
    label: string;
    value: number | string;
  }>;
};

type DashboardActivity = {
  id: string;
  __dom_id: string;
  dashboard_lifecycle_event_id: string;
  event_type: string;
  label: string;
  occurred: string;
  dashboard_version: number | null;
};

const props = defineProps<{
  surface: "header" | "versions" | "detail" | "activity";
  page: Page;
  selected_version_number?: number | null;
  selected_version_detail?: SelectedVersion | null;
  dashboard_versions?: DashboardVersion[];
  dashboard_activity?: DashboardActivity[];
}>();

const emit = defineEmits<{
  publish_version: [payload: { version: string }];
  restore_version: [payload: { version: string }];
}>();

const versions = computed(() => props.dashboard_versions ?? []);
const activity = computed(() => props.dashboard_activity ?? []);
</script>

<template>
  <CadencePageHeading v-if="surface === 'header'">
    <template #title>{{ page.header.heading }}</template>
    <template #eyebrow>{{ page.header.eyebrow }}</template>
    <template #description>{{ page.header.copy }}</template>
    <template #actions
      ><a
        v-if="page.actions.editor.visible"
        :id="page.actions.editor.id"
        :href="page.actions.editor.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-primary btn-sm"
      >
        {{ page.actions.editor.label }} </a
      ><a
        :id="page.actions.viewer.id"
        :href="page.actions.viewer.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-ghost btn-sm"
      >
        {{ page.actions.viewer.label }}
      </a></template
    >
  </CadencePageHeading>

  <nav v-if="surface === 'versions'" class="space-y-3" aria-label="Dashboard versions">
    <div class="flex items-center justify-between">
      <p class="hud-label">{{ page.versions.label }}</p>
      <span :id="page.versions.count_id" class="font-mono text-xs text-base-content/45">
        {{ page.versions.count }}
      </span>
    </div>
    <div :id="page.versions.container_id" class="space-y-2">
      <p
        v-if="versions.length === 0"
        :id="page.versions.empty_id"
        class="hidden only:block border border-dashed border-base-300 p-4 text-sm text-base-content/55"
      >
        {{ page.versions.empty }}
      </p>
      <a
        v-for="version in versions"
        :id="version.__dom_id"
        :key="version.__dom_id"
        :href="version.href"
        data-phx-link="patch"
        data-phx-link-state="push"
        :data-dashboard-version="version.version"
        :class="[
          'block border p-3 transition-colors',
          selected_version_number === version.version
            ? 'border-primary bg-primary/5'
            : 'border-base-300 hover:border-primary/40',
        ]"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="font-mono text-xs font-semibold">v{{ version.version }}</span>
          <span class="font-mono text-[0.6rem] uppercase text-base-content/45">
            {{ version.snapshot_kind }}
          </span>
        </div>
        <p class="mt-2 text-sm">{{ version.change_summary }}</p>
        <p class="mt-1 text-[0.65rem] text-base-content/45">
          {{ version.saved }}
        </p>
      </a>
    </div>
  </nav>

  <template v-if="surface === 'detail'">
    <template v-if="selected_version_detail">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="hud-label">Selected version</p>
          <h2 class="mt-1 text-xl font-semibold">Version {{ selected_version_detail.version }}</h2>
          <p class="mt-1 text-sm text-base-content/60">
            {{ selected_version_detail.change_summary }}
          </p>
        </div>
        <div v-if="selected_version_detail.actions.visible" class="flex gap-2">
          <button
            :id="selected_version_detail.actions.restore.id"
            type="button"
            class="btn btn-ghost btn-sm"
            :disabled="selected_version_detail.actions.restore.disabled"
            @click="emit('restore_version', selected_version_detail.actions.restore.payload)"
          >
            {{ selected_version_detail.actions.restore.label }}
          </button>
          <button
            :id="selected_version_detail.actions.publish.id"
            type="button"
            class="btn btn-primary btn-sm"
            :disabled="selected_version_detail.actions.publish.disabled"
            @click="emit('publish_version', selected_version_detail.actions.publish.payload)"
          >
            {{ selected_version_detail.actions.publish.label }}
          </button>
        </div>
      </div>
      <dl class="mt-5 grid gap-3 border-t border-base-300 pt-4 sm:grid-cols-3">
        <div v-for="detail in selected_version_detail.details" :key="detail.label">
          <dt class="hud-label">{{ detail.label }}</dt>
          <dd class="mt-1 font-mono text-sm">{{ detail.value }}</dd>
        </div>
      </dl>
    </template>
    <p v-else class="text-sm text-base-content/55">Select a version to inspect its saved state.</p>
  </template>

  <section v-if="surface === 'activity'" class="border border-base-300 bg-base-200/20 p-5">
    <div class="flex items-center justify-between">
      <p class="hud-label">{{ page.activity.label }}</p>
      <span :id="page.activity.count_id" class="font-mono text-xs text-base-content/45">
        {{ page.activity.count }}
      </span>
    </div>
    <div :id="page.activity.container_id" class="mt-3 divide-y divide-base-300/70">
      <p
        v-if="activity.length === 0"
        :id="page.activity.empty_id"
        class="hidden only:block py-4 text-sm text-base-content/55"
      >
        {{ page.activity.empty }}
      </p>
      <article
        v-for="event in activity"
        :id="event.__dom_id"
        :key="event.__dom_id"
        class="flex items-start gap-3 py-3"
        :data-dashboard-activity-type="event.event_type"
      >
        <span class="mt-1 h-2 w-2 rounded-full bg-primary"></span>
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium">{{ event.label }}</p>
          <p class="mt-0.5 font-mono text-[0.65rem] text-base-content/45">
            {{ event.occurred }}
          </p>
        </div>
        <span v-if="event.dashboard_version" class="font-mono text-xs text-base-content/50">
          v{{ event.dashboard_version }}
        </span>
      </article>
    </div>
  </section>
</template>
