<script setup lang="ts">
import { computed, inject, ref, onMounted } from "vue";
import { useQuery } from "@tanstack/vue-query";
import { useRoute } from "vue-router";
import {
  OpsContactSchedule,
  OpsContactRecord,
} from "@cadence/planning-and-contacts/contact-scheduling";
import { workspaceClientKey, WorkspaceRequestError } from "./client";

const client = inject(workspaceClientKey);
if (!client) throw Error("Missing contact client");
// The route outlet keys this component by URL. Each observer owns one resource/query.
const route = useRoute();
const search = route.fullPath.split("?")[1]?.split("#")[0];
const queryString = search ? `?${search}` : "";
const id = typeof route.params.contactId === "string" ? route.params.contactId : null;
const page = ref<HTMLElement>();
onMounted(() => page.value?.focus({ preventScroll: true }));
const schedulePort = client.scheduleService(queryString);
const recordPort = id ? client.recordPort(id, queryString) : undefined;
const query = useQuery(client.pageOptions(id, queryString));
const unavailable = computed(
  () =>
    query.error.value instanceof WorkspaceRequestError &&
    query.error.value.status >= 400 &&
    query.error.value.status < 500,
);
const disabled = computed(() => query.isPaused.value || query.isError.value);
function retry() {
  query.refetch().catch(() => {});
}
</script>
<template>
  <section
    ref="page"
    tabindex="-1"
    :aria-label="id ? 'Contact record' : 'Contact scheduling'"
    :data-contact-route="route.name"
    class="min-w-0"
  >
    <p v-if="query.isPending.value" id="contact-workspace-loading" role="status" class="p-6">
      {{ id ? "Loading contact record…" : "Loading contact scheduling…" }}
    </p>
    <p v-if="query.isPaused.value" id="contact-workspace-offline" role="status" class="px-6 py-2">
      Offline. Showing previously loaded data when available.
    </p>
    <div v-if="query.isError.value" id="contact-workspace-error" role="alert" class="p-6">
      <p>{{ query.error.value?.message }}</p>
      <button id="contact-workspace-retry" type="button" class="btn btn-sm mt-2" @click="retry">
        Retry
      </button>
    </div>
    <p v-if="query.data.value && query.isFetching.value" role="status" class="px-6 py-2 text-sm">
      Refreshing contact data…
    </p>
    <fieldset v-if="query.data.value && !unavailable" :disabled="disabled" class="min-w-0">
      <OpsContactRecord
        v-if="query.data.value.kind === 'record' && recordPort"
        :record="query.data.value.model"
        :port="recordPort"
      />
      <OpsContactSchedule
        v-else-if="query.data.value.kind === 'schedule'"
        :schedule="query.data.value.model"
        :port="schedulePort"
      />
    </fieldset>
  </section>
</template>
