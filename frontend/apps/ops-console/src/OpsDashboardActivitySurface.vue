<script setup lang="ts">
import OpsDashboardActivity from "./OpsDashboardActivity.vue";

const emit = defineEmits(["publish_version", "restore_version"]);

type Page = {
  id: string;
  header: { eyebrow: string; heading: string; copy: string };
  actions: {
    editor: { id: string; label: string; href: string; visible: boolean };
    viewer: { id: string; label: string; href: string };
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

type SelectedVersion = {
  version: number;
  change_summary: string;
  actions: {
    visible: boolean;
    restore: { id: string; label: string; disabled: boolean; payload: { version: string } };
    publish: { id: string; label: string; disabled: boolean; payload: { version: string } };
  };
  details: Array<{ label: string; value: number | string }>;
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

defineProps<{
  page: Page;
  selected_version_number?: number | null;
  selected_version_detail?: SelectedVersion | null;
  dashboard_versions?: DashboardVersion[];
  dashboard_activity?: DashboardActivity[];
}>();
</script>

<template>
  <main id="dashboard-activity-page" class="h-full overflow-y-auto bg-base-100">
    <OpsDashboardActivity surface="header" :page="page" />
    <div class="mx-auto grid max-w-[100rem] gap-5 p-5 lg:grid-cols-[22rem_minmax(0,1fr)] lg:p-7">
      <OpsDashboardActivity
        surface="versions"
        :page="page"
        :selected_version_number="selected_version_number"
        :dashboard_versions="dashboard_versions"
      />
      <div class="min-w-0 space-y-5">
        <section class="border border-base-300 bg-base-200/20 p-5">
          <OpsDashboardActivity
            surface="detail"
            :page="page"
            :selected_version_number="selected_version_number"
            :selected_version_detail="selected_version_detail"
            @publish_version="emit('publish_version', $event)"
            @restore_version="emit('restore_version', $event)"
          />
        </section>
        <OpsDashboardActivity
          surface="activity"
          :page="page"
          :dashboard_activity="dashboard_activity"
        />
      </div>
    </div>
  </main>
</template>
