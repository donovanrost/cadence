<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import { onBeforeUnmount, reactive, watch } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";

type Severity = "critical" | "warning" | "info" | "nominal";

type Option = {
  label: string;
  value: string;
};

type SelectField = {
  id: string;
  name: string;
  type: "select";
  label: string;
  options: Option[];
};

type SearchField = {
  id: string;
  name: string;
  type: "search";
  label: string;
  placeholder: string;
  debounce_ms: number;
};

type FilterValues = {
  severity: string;
  state: string;
  spacecraft_id: string;
  query: string;
};

type Alarm = {
  id: string;
  __dom_id: string;
  limit_event_id: string;
  severity: Severity;
  limit_state: string;
  state_label: string;
  point_name: string;
  context: string;
  value: {
    label: string;
    display: string;
  };
  observed: {
    label: string;
    display: string;
  };
  evidence: {
    id: string;
    href: string;
    title: string;
    icon: string;
    label: string;
  };
  definition: {
    id: string;
    href: string;
    title: string;
    icon: string;
    label: string;
  };
};

const props = defineProps<{
  page: {
    id: string;
    header: {
      eyebrow: string;
      heading: string;
      copy: string;
    };
    conditions_id: string;
  };
  summary: {
    id: string;
    active_count: number;
    observed: string;
    badges: Array<{
      severity: Exclude<Severity, "nominal">;
      count: number;
      label: string;
    }>;
  };
  filters: {
    id: string;
    values: FilterValues;
    fields: {
      severity: SelectField;
      state: SelectField;
      spacecraft_id: SelectField;
      query: SearchField;
    };
  };
  reset: {
    id: string;
    label: string;
  };
  empty: {
    id: string;
    icon: string;
    heading: string;
    copy: string;
  };
  alarms: Alarm[];
}>();

const emit = defineEmits<{
  filter: [payload: { filters: FilterValues }];
  reset_filters: [payload: Record<string, never>];
}>();

const severityClasses: Record<Severity, string> = {
  critical: "bg-error/20 text-error",
  warning: "bg-warning/20 text-warning",
  info: "bg-info/20 text-info",
  nominal: "bg-success/20 text-success",
};

const filterValues = reactive<FilterValues>({ ...props.filters.values });
let queryTimer: ReturnType<typeof setTimeout> | undefined;

watch(
  () => props.filters.values,
  (values) => {
    if (queryTimer !== undefined) clearTimeout(queryTimer);
    queryTimer = undefined;
    Object.assign(filterValues, values);
  },
  { deep: true },
);

onBeforeUnmount(() => {
  if (queryTimer !== undefined) clearTimeout(queryTimer);
});

const emitFilters = () => {
  emit("filter", { filters: { ...filterValues } });
};

const updateSelect = (key: "severity" | "state" | "spacecraft_id", event: Event) => {
  if (queryTimer !== undefined) clearTimeout(queryTimer);
  queryTimer = undefined;
  filterValues[key] = (event.target as HTMLSelectElement).value;
  emitFilters();
};

const updateQuery = (event: Event) => {
  filterValues.query = (event.target as HTMLInputElement).value;

  if (queryTimer !== undefined) clearTimeout(queryTimer);
  queryTimer = setTimeout(() => {
    queryTimer = undefined;
    emitFilters();
  }, props.filters.fields.query.debounce_ms);
};

const resetFilters = () => {
  if (queryTimer !== undefined) clearTimeout(queryTimer);
  queryTimer = undefined;
  emit("reset_filters", {});
};
</script>

<template>
  <CadenceOpsViewport :id="page.id">
    <CadencePageHeading>
      <template #title>{{ page.header.heading }}</template>
      <template #eyebrow>{{ page.header.eyebrow }}</template>
      <template #description>{{ page.header.copy }}</template>
      <template #actions
        ><div
          :id="summary.id"
          class="flex flex-wrap gap-2"
          :data-alarm-active-count="summary.active_count"
        >
          <span
            v-for="badge in summary.badges"
            :key="badge.severity"
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium"
            :class="severityClasses[badge.severity]"
          >
            <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
            <span class="font-mono">{{ badge.count }}</span>
            <span class="uppercase text-[0.65rem]">{{ badge.label }}</span>
          </span>
        </div></template
      >
    </CadencePageHeading>

    <CadenceOpsListBodyFrame>
      <form
        :id="filters.id"
        class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-4"
        @submit.prevent
      >
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="filters.fields.severity.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="filters.fields.severity.id"
            :name="filters.fields.severity.name"
            :value="filterValues.severity"
            class="w-full select"
            @change="updateSelect('severity', $event)"
          >
            <option
              v-for="option in filters.fields.severity.options"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="filters.fields.state.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="filters.fields.state.id"
            :name="filters.fields.state.name"
            :value="filterValues.state"
            class="w-full select"
            @change="updateSelect('state', $event)"
          >
            <option
              v-for="option in filters.fields.state.options"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="filters.fields.spacecraft_id.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="filters.fields.spacecraft_id.id"
            :name="filters.fields.spacecraft_id.name"
            :value="filterValues.spacecraft_id"
            class="w-full select"
            @change="updateSelect('spacecraft_id', $event)"
          >
            <option
              v-for="option in filters.fields.spacecraft_id.options"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="filters.fields.query.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="filters.fields.query.id"
            :name="filters.fields.query.name"
            :type="filters.fields.query.type"
            :value="filterValues.query"
            :placeholder="filters.fields.query.placeholder"
            class="w-full input"
            @input="updateQuery"
          />
        </CadenceField>
      </form>

      <div class="flex items-center justify-between gap-3">
        <p class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
          {{ summary.observed }}
        </p>
        <button :id="reset.id" type="button" class="btn btn-ghost btn-xs" @click="resetFilters">
          {{ reset.label }}
        </button>
      </div>

      <CadenceOpsListFrame>
        <div :id="page.conditions_id">
          <div
            :id="empty.id"
            class="hidden only:flex min-h-48 flex-col items-center justify-center px-6 text-center"
          >
            <span :class="[empty.icon, 'h-8 w-8 text-success/70']"></span>
            <p class="mt-3 font-semibold">{{ empty.heading }}</p>
            <p class="mt-1 text-sm text-base-content/55">
              {{ empty.copy }}
            </p>
          </div>
          <article
            v-for="alarm in alarms"
            :id="alarm.__dom_id"
            :key="alarm.id"
            :data-alarm-condition="alarm.limit_event_id"
            :data-alarm-severity="alarm.severity"
            :data-alarm-state="alarm.limit_state"
            class="grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 lg:grid-cols-[10rem_minmax(0,1fr)_12rem_12rem_auto] lg:items-center"
          >
            <span
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium"
              :class="severityClasses[alarm.severity]"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
              <span class="uppercase text-[0.65rem]">{{ alarm.state_label }}</span>
            </span>
            <div class="min-w-0">
              <p class="truncate font-semibold">{{ alarm.point_name }}</p>
              <p class="truncate font-mono text-[0.68rem] text-base-content/50">
                {{ alarm.context }}
              </p>
            </div>
            <div>
              <p class="hud-label">{{ alarm.value.label }}</p>
              <p class="mt-1 font-mono text-sm">{{ alarm.value.display }}</p>
            </div>
            <div>
              <p class="hud-label">{{ alarm.observed.label }}</p>
              <p class="mt-1 font-mono text-[0.68rem]">{{ alarm.observed.display }}</p>
            </div>
            <div class="flex justify-end gap-1">
              <a
                :id="alarm.evidence.id"
                :href="alarm.evidence.href"
                :title="alarm.evidence.title"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="btn btn-ghost btn-xs"
              >
                <span :class="[alarm.evidence.icon, 'h-3.5 w-3.5']"></span>
                {{ alarm.evidence.label }}
              </a>
              <a
                :id="alarm.definition.id"
                :href="alarm.definition.href"
                :title="alarm.definition.title"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="btn btn-ghost btn-xs"
              >
                <span :class="[alarm.definition.icon, 'h-3.5 w-3.5']"></span>
                {{ alarm.definition.label }}
              </a>
            </div>
          </article>
        </div>
      </CadenceOpsListFrame>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
