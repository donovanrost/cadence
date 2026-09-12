<script setup lang="ts">
import { computed, ref, watch } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import {
  endpointPageHref,
  spacecraftCommandingHref,
  type SpacecraftCommandingModel,
} from "./contracts";
const props = defineProps<{ model: SpacecraftCommandingModel }>();
const search = ref(props.model.query.query);
watch(
  () => props.model,
  (model) => {
    search.value = model.query.query;
  },
);
const base = computed(
  () =>
    `/missions/${encodeURIComponent(props.model.context.missionId)}/spacecraft/${encodeURIComponent(props.model.context.spacecraftId)}`,
);
const mission = computed(() => `/missions/${encodeURIComponent(props.model.context.missionId)}`);
const pages = computed(() => Math.max(1, Math.ceil(props.model.endpoints.total_count / 25)));
const profileLabel = computed(
  () =>
    ({
      ready: "Pinned profile",
      unbound: "No profile selected",
      unavailable: "Pinned profile unavailable",
    })[props.model.profile.status],
);
const monitorHref = (id: string) =>
  `${mission.value}/ops/commands?${new URLSearchParams({ target: id })}`;
</script>
<template>
  <div id="spacecraft-commanding-page" class="space-y-6">
    <CadencePageHeading>
      <template #title>Commanding for {{ model.spacecraft_name }}</template>
      <template #eyebrow>{{ model.mission_name }} · Command interpretation</template>
      <template #description
        >Review this spacecraft's pinned protocols and command target identities.</template
      >
      <template #actions
        ><a :href="base" class="btn btn-sm btn-ghost">Spacecraft overview</a
        ><a :href="endpointPageHref(model, model.query.page)" class="btn btn-sm"
          >Refresh evidence</a
        ></template
      >
    </CadencePageHeading>
    <CadenceCard body-class="p-5 space-y-4">
      <h2 id="spacecraft-commanding-profile" class="text-lg font-semibold">{{ profileLabel }}</h2>
      <dl class="grid gap-4 sm:grid-cols-2">
        <div>
          <dt class="hud-label">Spacecraft SCID</dt>
          <dd class="mt-1 font-mono break-all">{{ model.scid ?? "Not set" }}</dd>
        </div>
        <div>
          <dt class="hud-label">Profile reference</dt>
          <dd class="mt-1 font-mono break-all">
            {{ model.profile.id ?? "None"
            }}<span v-if="model.profile.version !== null"> · v{{ model.profile.version }}</span>
          </dd>
        </div>
        <template v-if="model.profile.status === 'ready'">
          <div>
            <dt class="hud-label">Profile</dt>
            <dd class="mt-1">{{ model.profile.name }} · {{ model.profile.lifecycle }}</dd>
          </div>
          <div>
            <dt class="hud-label">Uplink protocol</dt>
            <dd class="mt-1 font-mono uppercase">{{ model.profile.uplink }}</dd>
          </div>
          <div>
            <dt class="hud-label">Packet protocol</dt>
            <dd class="mt-1 font-mono">CCSDS space packet</dd>
          </div>
        </template>
      </dl>
      <p v-if="model.profile.lifecycle === 'deleted'" role="status" class="text-warning">
        The pinned profile version is deleted. Review the spacecraft binding before operations.
      </p>
      <p v-if="model.profile.status === 'unavailable'" role="status" class="text-warning">
        The selected profile version could not be read. Its protocols are unavailable.
      </p>
      <p class="text-sm text-base-content/70">
        These are configuration records. They do not confirm command encoding, active transport
        configuration, or permission to release a command.
      </p>
      <div class="flex flex-wrap gap-3">
        <a id="commanding-edit-identity" :href="`${base}/identity`" class="btn btn-sm"
          >Review identity and profile</a
        >
        <a :href="`${base}/routing`" class="btn btn-sm btn-ghost">Review routing</a>
        <a :href="`${base}/readiness`" class="btn btn-sm btn-ghost">Review readiness</a>
      </div>
    </CadenceCard>
    <CadenceCard body-class="p-5 space-y-4">
      <div>
        <h2 class="text-lg font-semibold">Command target identities</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Source endpoints assigned to this spacecraft. Open an endpoint's command monitor to
          inspect requests and their evidence.
        </p>
      </div>
      <form
        id="commanding-endpoint-filter"
        method="get"
        :action="spacecraftCommandingHref(model.context.missionId, model.context.spacecraftId)"
        class="flex flex-wrap items-end gap-3"
      >
        <CadenceField label="Find an endpoint" control-id="commanding-endpoint-search"
          ><input
            id="commanding-endpoint-search"
            v-model="search"
            name="query"
            maxlength="240"
            class="input w-full"
        /></CadenceField>
        <button type="submit" class="btn btn-sm">Search</button>
        <a
          :href="spacecraftCommandingHref(model.context.missionId, model.context.spacecraftId)"
          class="btn btn-sm btn-ghost"
          >Reset</a
        >
      </form>
      <p class="text-sm font-mono">{{ model.endpoints.total_count }} matching endpoints</p>
      <p
        v-if="model.endpoints.items.length === 0"
        id="commanding-endpoints-empty"
        class="text-sm text-base-content/70"
      >
        No source endpoints match this spacecraft and search.
      </p>
      <ul v-else id="commanding-endpoints" class="divide-y divide-base-300">
        <li
          v-for="endpoint in model.endpoints.items"
          :key="endpoint.id"
          :data-endpoint="endpoint.id"
          class="py-4 space-y-2"
        >
          <h3 class="font-semibold break-words">{{ endpoint.name || endpoint.id }}</h3>
          <p class="font-mono text-sm break-all">
            <span class="block">{{ endpoint.id }}</span
            ><span class="block break-normal">SCID {{ endpoint.scid ?? "not set" }}</span>
          </p>
          <a v-if="endpoint.id !== 'all'" :href="monitorHref(endpoint.id)" class="link text-sm"
            >Open command monitor</a
          >
          <p v-else class="text-sm">
            This endpoint uses the monitor's reserved all-targets value. Inspect request identities
            in the mission monitor.
          </p>
        </li>
      </ul>
      <nav
        aria-label="Source endpoint pages"
        class="flex flex-wrap justify-between items-center gap-3"
      >
        <a
          v-if="model.query.page > 1"
          :href="endpointPageHref(model, model.query.page - 1)"
          class="link text-sm"
          >Previous endpoints</a
        >
        <span class="text-sm font-mono">Page {{ model.query.page }} of {{ pages }}</span>
        <a
          v-if="model.query.page < pages"
          :href="endpointPageHref(model, model.query.page + 1)"
          class="link text-sm"
          >Next endpoints</a
        >
      </nav>
      <a :href="`${mission}/ops/commands`" class="link text-sm">Open mission command monitor</a>
    </CadenceCard>
  </div>
</template>
