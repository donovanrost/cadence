<script setup lang="ts">
import { computed } from "vue";
import CadenceTechnicalDetails from "@cadence/ui/CadenceTechnicalDetails.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
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

const props = defineProps<{
  revision: Revision;
  navigation: Navigation;
  provenance: DetailCard;
  spacecraft_usage: unknown;
  mission_model: MissionModel;
}>();

// These rows describe diagnostic provenance; operational labels and counts remain visible.
const diagnosticProvenance = (row: DetailRow) =>
  row.label === "Import run" || row.label === "Content SHA-256";
const modelIdentifier = (row: DetailRow) => row.label === "Revision" && row.style === "hash";
const provenanceDetails = computed(() => props.provenance.rows.filter(diagnosticProvenance));
const sourceRows = computed(() =>
  props.provenance.rows.filter((row) => !diagnosticProvenance(row)),
);
const modelRows = computed(() => props.mission_model.rows.filter((row) => !modelIdentifier(row)));
const technicalItems = computed(() => [
  ...provenanceDetails.value.map((row) => ({
    label: row.label,
    value: row.value === null ? null : String(row.value),
    href: row.href,
  })),
  ...props.mission_model.rows.filter(modelIdentifier).map((row) => ({
    label: "Model revision ID",
    value: row.value === null ? null : String(row.value),
    href: row.href,
  })),
]);
useManagementHeader("/missions/:mission_id/catalog/revisions/:catalog_revision_id", () => ({
  title: props.revision.title,
  facts: [props.revision.number_label],
}));
</script>

<template>
  <div id="catalog-revision-show-surface" class="space-y-6">
    <CadenceCard
      :id="provenance.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
      <p class="hud-label">Imported definitions</p>
      <div class="mt-3 divide-y divide-base-300">
        <CadenceDataRow
          v-for="row in sourceRows"
          :key="row.label"
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="row.label"
        >
          <span class="hud-data-value">
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

    <CadenceCard
      :id="mission_model.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
      <p class="hud-label">{{ mission_model.title }}</p>
      <div v-if="mission_model.available" class="mt-3 divide-y divide-base-300">
        <CadenceDataRow
          v-for="row in modelRows"
          :key="row.label"
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="row.label"
        >
          <span class="hud-data-value">
            {{ row.value ?? "—" }}
          </span>
        </CadenceDataRow>
      </div>
      <p v-else class="mt-2 text-sm text-base-content/60">
        {{ mission_model.empty_message }}
      </p>
    </CadenceCard>
    <CatalogSpacecraftUsage :data="spacecraft_usage" />
    <CadenceTechnicalDetails
      id="catalog-revision-technical-details"
      :summary="provenance.title"
      :context="revision.title"
      :items="technicalItems"
    />
  </div>
</template>
