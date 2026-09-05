<script setup lang="ts">
import CadenceOpsViewport from "./ui/components/CadenceOpsViewport.vue";
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue";
import CadenceField from "./ui/components/CadenceField.vue";
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue";
import CadenceOpsListFrame from "./ui/components/CadenceOpsListFrame.vue";
import CadenceOpsListBodyFrame from "./ui/components/CadenceOpsListBodyFrame.vue";
import { computed, reactive, ref, watch } from "vue";

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
  status: string;
  target: string;
  query: string;
};

type EmptyPayload = Record<string, never>;
type FollowPayload = { "command-request-id": string };

type Command = {
  id: string;
  __dom_id: string;
  command_request_id: string;
  command_name: string;
  status: {
    value: string;
    label: string;
    class: string;
  };
  target: {
    label: string;
    display: string | null;
  };
  requester: {
    label: string;
    display: string;
  };
  age: {
    label: string;
    display: string;
  };
  focus: {
    following: boolean;
    label: string;
    class: string;
    action: {
      id: string;
      label: string;
      icon: string;
      payload: FollowPayload;
    };
  };
  evidence: {
    summary: string;
    request_state: {
      label: string;
      display: string;
    };
    queue_entry: {
      label: string;
      record_id: string | null;
      display: string;
    };
    release_attempt: {
      label: string;
      record_id: string | null;
      display: string;
    };
    verification: {
      label: string;
      state: string | null;
      display: string;
    };
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
    rows_id: string;
  };
  summary: {
    id: string;
    active_count: number;
    observed: string;
    metrics: Array<{
      label: string;
      value: number;
      value_class: string;
    }>;
  };
  filters: {
    id: string;
    values: FilterValues;
    fields: {
      status: SelectField;
      target: SelectField;
      query: SearchField;
    };
  };
  reset: {
    id: string;
    label: string;
    payload: EmptyPayload;
  };
  focus_banner: {
    id: string;
    command_request_id: string;
    icon: string;
    prefix: string;
    suffix: string;
    clear: {
      id: string;
      label: string;
      payload: EmptyPayload;
    };
  } | null;
  empty: {
    id: string;
    icon: string;
    heading: string;
    copy: string;
  };
  commands: Command[];
}>();

const filterValues = reactive<FilterValues>({ ...props.filters.values });
const focusedCommandRequestId = ref(props.focus_banner?.command_request_id ?? null);

watch(
  () => props.filters.values,
  (values) => {
    Object.assign(filterValues, values);
  },
  { deep: true },
);

const updateSelect = (key: "status" | "target", event: Event) => {
  filterValues[key] = (event.target as HTMLSelectElement).value;
};

const updateQuery = (event: Event) => {
  filterValues.query = (event.target as HTMLInputElement).value;
};

const resetFilters = () => {
  Object.assign(filterValues, props.reset.payload);
  filterValues.status = "all";
  filterValues.target = "all";
  filterValues.query = "";
};

const followCommand = (command: Command) => {
  focusedCommandRequestId.value = command.focus.action.payload["command-request-id"];
};

const clearCommandFocus = () => {
  focusedCommandRequestId.value = null;
};

const visibleCommands = computed(() => {
  const status = filterValues.status;
  const target = filterValues.target;
  const query = filterValues.query.toLowerCase();

  return props.commands
    .filter((command) => {
      const statusMatches = status === "" || status === "all" || command.status.value === status;
      const targetMatches =
        target === "" || target === "all" || command.target.display === target;
      const queryMatches =
        query === "" ||
        [
          command.command_name,
          command.command_request_id,
          command.target.display,
          command.requester.display,
        ].some((value) => value?.toLowerCase().includes(query));

      return statusMatches && targetMatches && queryMatches;
    })
    .map((command) => ({
      ...command,
      focus: {
        ...command.focus,
        following: command.command_request_id === focusedCommandRequestId.value,
      },
    }));
});

const focusBanner = computed(() => {
  const commandRequestId = focusedCommandRequestId.value;
  if (!commandRequestId) return null;

  return props.focus_banner
    ? { ...props.focus_banner, command_request_id: commandRequestId }
    : {
        id: "followed-command-banner",
        command_request_id: commandRequestId,
        icon: "hero-eye",
        prefix: "Following",
        suffix: "across Ops pages",
        clear: { id: "clear-command-focus", label: "Stop following", payload: {} },
      };
});
</script>

<template>
  <CadenceOpsViewport :id="page.id">
    <CadencePageHeaderFrame variant="ops">
      <div
        class="mx-auto flex max-w-[100rem] flex-col gap-5 xl:flex-row xl:items-end xl:justify-between"
      >
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.heading }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            {{ page.header.copy }}
          </p>
        </div>
        <div
          :id="summary.id"
          class="grid grid-cols-2 gap-px border border-base-300 bg-base-300 sm:grid-cols-4"
          :data-command-active-count="summary.active_count"
        >
          <div
            v-for="metric in summary.metrics"
            :key="metric.label"
            class="min-w-24 bg-base-100/80 px-3 py-2"
          >
            <p class="hud-label">{{ metric.label }}</p>
            <p class="mt-1 font-mono text-lg font-semibold" :class="metric.value_class">
              {{ metric.value }}
            </p>
          </div>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <CadenceOpsListBodyFrame>
      <div
          v-if="focusBanner"
          :id="focusBanner.id"
          :data-followed-command="focusBanner.command_request_id"
        class="flex items-center gap-3 border-l-2 border-info bg-info/10 px-3 py-2"
      >
          <span :class="[focusBanner.icon, 'h-4 w-4 text-info']"></span>
        <p class="min-w-0 flex-1 truncate text-sm">
          {{ focusBanner.prefix }}
          <span class="font-mono font-semibold">{{ focusBanner.command_request_id }}</span>
          {{ focusBanner.suffix }}
        </p>
          <button
            :id="focusBanner.clear.id"
          type="button"
          class="btn btn-ghost btn-xs"
          @click="clearCommandFocus"
        >
          {{ focusBanner.clear.label }}
        </button>
      </div>

      <form
        :id="filters.id"
        class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-3"
        @submit.prevent
      >
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="filters.fields.status.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="filters.fields.status.id"
            :name="filters.fields.status.name"
            :value="filterValues.status"
            class="w-full select"
            @change="updateSelect('status', $event)"
          >
            <option
              v-for="option in filters.fields.status.options"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="filters.fields.target.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="filters.fields.target.id"
            :name="filters.fields.target.name"
            :value="filterValues.target"
            class="w-full select"
            @change="updateSelect('target', $event)"
          >
            <option
              v-for="option in filters.fields.target.options"
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
        <div :id="page.rows_id">
          <div
            :id="empty.id"
            class="hidden only:flex min-h-48 flex-col items-center justify-center px-6 text-center"
          >
            <span :class="[empty.icon, 'h-8 w-8 text-base-content/30']"></span>
            <p class="mt-3 font-semibold">{{ empty.heading }}</p>
            <p class="mt-1 text-sm text-base-content/55">
              {{ empty.copy }}
            </p>
          </div>
          <article
            v-for="command in visibleCommands"
            :id="command.__dom_id"
            :key="command.id"
            :data-command-request="command.command_request_id"
            :data-command-state="command.status.value"
            class="grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 xl:grid-cols-[9rem_minmax(0,1fr)_13rem_10rem_10rem_auto] xl:items-center"
          >
            <span :class="command.status.class">{{ command.status.label }}</span>
            <div class="min-w-0">
              <p class="truncate font-semibold">{{ command.command_name }}</p>
              <p class="truncate font-mono text-[0.68rem] text-base-content/50">
                {{ command.command_request_id }}
              </p>
            </div>
            <div>
              <p class="hud-label">{{ command.target.label }}</p>
              <p class="mt-1 truncate font-mono text-[0.68rem]">{{ command.target.display }}</p>
            </div>
            <div>
              <p class="hud-label">{{ command.requester.label }}</p>
              <p class="mt-1 truncate text-xs">{{ command.requester.display }}</p>
            </div>
            <div>
              <p class="hud-label">{{ command.age.label }}</p>
              <p class="mt-1 font-mono text-[0.68rem]">{{ command.age.display }}</p>
            </div>
            <div class="flex justify-end">
              <button
                v-if="!command.focus.following"
                :id="command.focus.action.id"
                type="button"
                class="btn btn-ghost btn-xs"
                @click="followCommand(command)"
              >
                <span :class="[command.focus.action.icon, 'h-3.5 w-3.5']"></span>
                {{ command.focus.action.label }}
              </button>
              <span v-else :class="command.focus.class">
                {{ command.focus.label }}
              </span>
            </div>
            <CadenceDetailsFrame class="xl:col-span-6 border-t border-base-300/50 pt-2">
              <summary
                class="cursor-pointer font-mono text-[0.65rem] uppercase tracking-wider text-base-content/50"
              >
                {{ command.evidence.summary }}
              </summary>
              <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2 lg:grid-cols-4">
                <div>
                  <dt class="hud-label">{{ command.evidence.request_state.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.request_state.display }}
                  </dd>
                </div>
                <div>
                  <dt class="hud-label">{{ command.evidence.queue_entry.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.queue_entry.display }}
                  </dd>
                </div>
                <div>
                  <dt class="hud-label">{{ command.evidence.release_attempt.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.release_attempt.display }}
                  </dd>
                </div>
                <div>
                  <dt class="hud-label">{{ command.evidence.verification.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.verification.display }}
                  </dd>
                </div>
              </dl>
            </CadenceDetailsFrame>
          </article>
        </div>
      </CadenceOpsListFrame>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
