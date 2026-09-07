<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Navigation = {
  breadcrumbs: Breadcrumb[];
};

type Detail = {
  label: string;
  value: string;
};

type GroundStation = {
  display_name: string;
  ground_station_id: string;
  lifecycle_state: string;
  details_title: string;
  description: string;
  details: Detail[];
  metadata_title: string;
  metadata_json: string;
};

type Action = {
  id: string;
  label: string;
};

type Actions = {
  edit: Action & { href: string };
  archive: Action & { confirm: string };
};

const props = defineProps<{
  navigation: Navigation;
  ground_station: GroundStation;
  actions: Actions;
}>();

const emit = defineEmits<{
  archive: [];
}>();

const archive = () => {
  if (window.confirm(props.actions.archive.confirm)) emit("archive");
};
</script>

<template>
  <div class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title>{{ ground_station.display_name }} </template>
      <template #description>{{ ground_station.ground_station_id }}</template>
      <template #metadata
        ><span>
          {{ ground_station.lifecycle_state }}
        </span></template
      >
      <template #actions
        ><a
          :id="actions.edit.id"
          :href="actions.edit.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm"
          >{{ actions.edit.label }}</a
        ><button
          :id="actions.archive.id"
          type="button"
          class="btn btn-ghost btn-sm"
          :data-confirm="actions.archive.confirm"
          @click="archive"
        >
          {{ actions.archive.label }}
        </button></template
      >
    </CadencePageHeading>

    <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
        <p class="hud-label">{{ ground_station.details_title }}</p>
        <p class="text-sm text-base-content/70">
          {{ ground_station.description }}
        </p>

        <div class="mt-6 space-y-1">
          <CadenceDataRow
            v-for="detail in ground_station.details"
            :key="detail.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="detail.label"
          >
            <span class="hud-data-value">{{ detail.value }}</span>
          </CadenceDataRow>
        </div>
      </CadenceCard>

      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
        <p class="hud-label">{{ ground_station.metadata_title }}</p>
        <pre class="overflow-x-auto font-mono text-xs text-base-content/70">{{
          ground_station.metadata_json
        }}</pre>
      </CadenceCard>
    </div>
  </div>
</template>
