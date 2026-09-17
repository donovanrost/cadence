<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import CatalogSpacecraftUsage from "./CatalogSpacecraftUsage.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Navigation = {
  breadcrumbs: Breadcrumb[];
};

type Revision = {
  title: string;
  number_label: string;
};

type DetailRow = {
  label: string;
  value: string | number | null;
  href: string | null;
  style: "default" | "mono" | "hash";
};

type DetailCard = {
  id: string;
  title: string;
  rows: DetailRow[];
};

type MissionModel = DetailCard & {
  available: boolean;
  empty_message: string;
};

defineProps<{
  revision: Revision;
  navigation: Navigation;
  provenance: DetailCard;
  spacecraft_usage: unknown;
  mission_model: MissionModel;
}>();

const valueClasses: Record<DetailRow["style"], string> = {
  default: "",
  mono: "font-mono",
  hash: "font-mono text-xs break-all",
};
</script>

<template>
  <div id="catalog-revision-show-surface" class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title>{{ revision.title }} </template>
      <template #metadata
        ><span>
          {{ revision.number_label }}
        </span></template
      >
    </CadencePageHeading>

    <CadenceCard
      :id="provenance.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
      <p class="hud-label">{{ provenance.title }}</p>
      <div class="mt-3 divide-y divide-base-300">
        <CadenceDataRow
          v-for="row in provenance.rows"
          :key="row.label"
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="row.label"
        >
          <span class="hud-data-value" :class="valueClasses[row.style]">
            <a
              v-if="row.href !== null && row.value !== null"
              :href="row.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="hover:underline"
              >{{ row.value }}</a
            >
            <span v-else>{{ row.value ?? "—" }}</span>
          </span>
        </CadenceDataRow>
      </div>
    </CadenceCard>

    <CatalogSpacecraftUsage :data="spacecraft_usage" />
    <CadenceCard
      :id="mission_model.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
      <p class="hud-label">{{ mission_model.title }}</p>
      <div v-if="mission_model.available" class="mt-3 divide-y divide-base-300">
        <CadenceDataRow
          v-for="row in mission_model.rows"
          :key="row.label"
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="row.label"
        >
          <span class="hud-data-value" :class="valueClasses[row.style]">
            {{ row.value ?? "—" }}
          </span>
        </CadenceDataRow>
      </div>
      <p v-else class="mt-2 text-sm text-base-content/60">
        {{ mission_model.empty_message }}
      </p>
    </CadenceCard>
  </div>
</template>
