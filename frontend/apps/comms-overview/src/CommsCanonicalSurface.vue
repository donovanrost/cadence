<script setup lang="ts">
import { computed } from "vue";
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue";
import CadenceCard from "./ui/components/CadenceCard.vue";
import CadenceCompactPageHeaderBodyFrame from "./ui/components/CadenceCompactPageHeaderBodyFrame.vue";
import CadenceDataRow from "./ui/components/CadenceDataRow.vue";
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue";
import CadenceHoverTableRow from "./ui/components/CadenceHoverTableRow.vue";
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue";
import CadencePageTitle from "./ui/components/CadencePageTitle.vue";
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue";
import CommsOverviewPage from "./CommsOverviewPage.vue";
import StatusBadge from "./StatusBadge.vue";
import { isCommsOverviewPresentation, type CommsOverviewPresentation } from "./comms-overview";

type SurfaceId =
  | "overview"
  | "validation"
  | "transports"
  | "transport"
  | "routing"
  | "routing_detail"
  | "ground_stations"
  | "ground_station";

type SurfacePayload = {
  navigation: {
    fallback_href: string;
    breadcrumbs: Array<{ label: string; href: string | null }>;
  };
  data: Record<string, unknown>;
};

const props = defineProps<{
  surfaceId: SurfaceId;
  payload: SurfacePayload;
}>();

const data = computed(() => props.payload.data);
const breadcrumbs = computed(() => props.payload.navigation.breadcrumbs);
const overviewPresentation = computed<CommsOverviewPresentation | undefined>(() =>
  isCommsOverviewPresentation(data.value) ? data.value : undefined,
);

const surfaceLabels: Record<SurfaceId, string> = {
  overview: "Overview",
  validation: "Validation",
  transports: "Transports",
  transport: "Transport",
  routing: "Routing",
  routing_detail: "Routing Rule",
  ground_stations: "Ground Stations",
  ground_station: "Ground Station",
};

const rootId = computed(() => text("id", `comms-${props.surfaceId.replaceAll("_", "-")}-surface`));
const title = computed(() => text("title", surfaceLabels[props.surfaceId]));
const subtitle = computed(() => {
  if (typeof data.value.subtitle === "string") return data.value.subtitle;
  if (props.surfaceId === "validation") {
    return "Actionable checks for saved spacecraft, transport, routing, and runtime setup.";
  }
  if (props.surfaceId === "transports") {
    return "Durable byte-moving capabilities Cadence can use for spacecraft traffic.";
  }
  if (props.surfaceId === "routing") {
    return "Durable rules describing how spacecraft use mission transports.";
  }
  if (props.surfaceId === "ground_stations") {
    return "Mission-owned antenna and site identities used by Comms setup.";
  }
  return "Mission-scoped communications configuration owned by Phoenix.";
});

const items = computed(() => listValue("items"));
const findings = computed(() => listValue("findings"));
const findingGroups = computed(() => listValue("finding_groups"));
const isCollection = computed(() =>
  ["transports", "routing", "ground_stations"].includes(props.surfaceId),
);
const isDetail = computed(() =>
  ["transport", "routing_detail", "ground_station"].includes(props.surfaceId),
);
const statusTone = computed(() => {
  const status = text("status", "attention");
  return status === "ready" ? "ready" : "attention";
});

function text(key: string, fallback: string): string {
  const value = data.value[key];
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function listValue(key: string): Array<Record<string, unknown>> {
  const value = data.value[key];
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

function rowId(item: Record<string, unknown>): string {
  return `${props.surfaceId}-${textValue(item, "id", "row")}`;
}

function textValue(item: Record<string, unknown>, key: string, fallback: string): string {
  const value = item[key];
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function hrefValue(item: Record<string, unknown>): string | null {
  const href = item.href;
  return typeof href === "string" && href.length > 0 ? href : null;
}

function displayValue(value: unknown): string {
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if (typeof value === "number") return String(value);
  return typeof value === "string" ? value : "Unavailable";
}

function detailEntries(): Array<[string, string]> {
  const hidden = new Set(["id", "href", "list_href", "edit_href"]);
  return Object.entries(data.value)
    .filter(
      ([key, value]) => !hidden.has(key) && ["string", "number", "boolean"].includes(typeof value),
    )
    .map(([key, value]) => [key.replaceAll("_", " "), displayValue(value)]);
}

function findingTone(finding: Record<string, unknown>): "blocked" | "attention" {
  return textValue(finding, "severity", "Warning") === "Blocking" ? "blocked" : "attention";
}

function findingLabel(finding: Record<string, unknown>): string {
  return textValue(finding, "severity", "Warning");
}

function actionHrefValue(finding: Record<string, unknown>): string | null {
  const href = finding.action_href;
  return typeof href === "string" && href.length > 0 ? href : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
</script>

<template>
  <CommsOverviewPage
    v-if="props.surfaceId === 'overview' && overviewPresentation"
    :presentation="overviewPresentation"
  />

  <div v-else :id="rootId" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <CadenceCompactPageHeaderBodyFrame>
        <template #content>
          <CadenceBreadcrumbs>
            <template
              v-for="(breadcrumb, index) in breadcrumbs"
              :key="`${index}-${breadcrumb.label}`"
            >
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span v-if="breadcrumb.href === null" class="text-primary/90">
                {{ breadcrumb.label }}
              </span>
              <a
                v-else
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
                >{{ breadcrumb.label }}</a
              >
            </template>
          </CadenceBreadcrumbs>

          <CadencePageTitle>
            {{ title }}
            <span class="ml-3 font-mono text-base text-base-content/60">
              {{ text("finding_count", text("total_count", "")) }}
            </span>
          </CadencePageTitle>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ subtitle }}</p>
        </template>
        <template #actions>
          <StatusBadge
            v-if="props.surfaceId === 'validation'"
            :status="statusTone"
            :label="text('status', 'Attention')"
          />
        </template>
      </CadenceCompactPageHeaderBodyFrame>
    </CadencePageHeaderFrame>

    <template v-if="props.surfaceId === 'validation'">
      <CadenceCard
        v-if="data.empty === true"
        id="comms-validation-empty"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <div class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center">
          <p class="hud-label">All clear</p>
          <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
            The saved configuration looks consistent.
          </p>
        </div>
      </CadenceCard>
      <div v-else id="comms-validation-findings" class="space-y-5">
        <CadenceCard
          v-for="group in findingGroups"
          :id="textValue(group, 'id', 'comms-validation-group')"
          :key="textValue(group, 'id', 'comms-validation-group')"
          class="card bg-base-200 border border-base-300"
          body-class="card-body p-0"
        >
          <div class="border-b border-base-300 px-4 py-3">
            <h2 class="text-base font-semibold text-base-content">
              {{ textValue(group, "title", "Comms findings") }}
            </h2>
            <p class="mt-1 text-xs text-base-content/70">
              {{ textValue(group, "description", "Review the saved Comms configuration.") }}
            </p>
          </div>
          <div class="divide-y divide-base-300">
            <div
              v-for="(finding, index) in Array.isArray(group.findings)
                ? group.findings.filter(isRecord)
                : []"
              :id="textValue(finding, 'id', `finding-${index + 1}`)"
              :key="textValue(finding, 'id', `${textValue(group, 'id', 'group')}-${index}`)"
              class="px-4 py-4"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <h3 class="font-semibold">{{ textValue(finding, "title", "Comms finding") }}</h3>
                  <p class="mt-1 text-sm text-base-content/70">
                    {{ textValue(finding, "body", "Review the saved Comms configuration.") }}
                  </p>
                  <a
                    v-if="actionHrefValue(finding)"
                    :href="actionHrefValue(finding) ?? undefined"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="btn btn-primary btn-xs mt-3"
                    >{{ textValue(finding, "action_label", "Review") }}</a
                  >
                </div>
                <StatusBadge :status="findingTone(finding)" :label="findingLabel(finding)" />
              </div>
            </div>
          </div>
        </CadenceCard>
        <span v-if="findings.length === 0" class="sr-only">No findings</span>
      </div>
    </template>

    <template v-else-if="isCollection">
      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-0">
        <div class="flex items-center justify-between gap-3 border-b border-base-300 px-4 py-3">
          <p class="hud-label">{{ text("total_count", "0") }} configured</p>
          <a
            v-if="props.surfaceId !== 'routing' || typeof data.href === 'string'"
            :href="`${props.payload.navigation.fallback_href}/new`"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm"
            >New {{ surfaceLabels[props.surfaceId].replace(/s$/, "") }}</a
          >
        </div>
        <CadenceTableFrame :id="`${props.surfaceId}-table`">
          <thead>
            <tr>
              <th class="hud-label">Name</th>
              <th v-if="props.surfaceId === 'transports'" class="hud-label">Origin</th>
              <th v-if="props.surfaceId === 'transports'" class="hud-label">Capability</th>
              <th v-if="props.surfaceId === 'routing'" class="hud-label">Spacecraft</th>
              <th v-if="props.surfaceId === 'routing'" class="hud-label">Transport</th>
              <th v-if="props.surfaceId === 'ground_stations'" class="hud-label">Provider</th>
              <th v-if="props.surfaceId === 'ground_stations'" class="hud-label">Region</th>
            </tr>
          </thead>
          <tbody :id="`${props.surfaceId}-rows`">
            <CadenceHoverTableRow v-for="item in items" :id="rowId(item)" :key="rowId(item)">
              <td class="font-medium">
                <a
                  v-if="hrefValue(item)"
                  :href="hrefValue(item) ?? undefined"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="text-primary hover:underline"
                  >{{ textValue(item, "display_name", "Unavailable") }}</a
                >
                <span v-else>{{ textValue(item, "display_name", "Unavailable") }}</span>
              </td>
              <td v-if="props.surfaceId === 'transports'" class="font-mono text-xs uppercase">
                {{ textValue(item, "origin", "Unavailable") }}
              </td>
              <td v-if="props.surfaceId === 'transports'" class="font-mono text-xs uppercase">
                {{ textValue(item, "transport_kind", "Unavailable") }} ·
                {{ textValue(item, "direction_capability", "Unavailable") }}
              </td>
              <td v-if="props.surfaceId === 'routing'">
                {{ textValue(item, "spacecraft_name", "Unavailable") }}
              </td>
              <td v-if="props.surfaceId === 'routing'">
                {{ textValue(item, "transport_name", "Unavailable") }}
              </td>
              <td v-if="props.surfaceId === 'ground_stations'" class="font-mono text-xs uppercase">
                {{ textValue(item, "provider", "Unavailable") }}
              </td>
              <td v-if="props.surfaceId === 'ground_stations'" class="font-mono text-xs">
                {{ textValue(item, "region", "Unavailable") }}
              </td>
            </CadenceHoverTableRow>
          </tbody>
        </CadenceTableFrame>
        <p v-if="items.length === 0" class="px-4 py-6 text-center text-sm text-base-content/70">
          No {{ surfaceLabels[props.surfaceId].toLowerCase() }} configured.
        </p>
      </CadenceCard>
    </template>

    <template v-else-if="isDetail">
      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
          <p class="hud-label">Configuration</p>
          <div class="mt-6 space-y-1">
            <CadenceDataRow
              v-for="[label, value] in detailEntries()"
              :key="label"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="label"
            >
              <span class="hud-data-value">{{ value }}</span>
            </CadenceDataRow>
          </div>
        </CadenceCard>
        <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
          <p class="hud-label">Phoenix authority</p>
          <p class="mt-2 text-sm text-base-content/70">
            CRUD, validation, CSRF, and redirects remain owned by the Phoenix fallback surface.
          </p>
          <a
            :href="props.payload.navigation.fallback_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm mt-5"
            >Open Phoenix surface</a
          >
        </CadenceCard>
      </div>
      <CadenceDetailsFrame class="rounded border border-base-300 bg-base-100/40 p-4 text-sm">
        <summary class="cursor-pointer hud-label hover:text-primary">Surface contract</summary>
        <pre class="mt-3 max-h-96 overflow-auto font-mono text-xs text-base-content/70">{{
          JSON.stringify(data, null, 2)
        }}</pre>
      </CadenceDetailsFrame>
    </template>
  </div>
</template>
