<script setup lang="ts">
import { computed, ref } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceStatTile from "@cadence/ui/CadenceStatTile.vue";
import type { PacketDocument, PacketPort } from "./contracts";
import { usePacketBindings } from "./state";
const props = defineProps<{ initial: PacketDocument; port: PacketPort }>();
const state = usePacketBindings(() => props.initial, props.port);
const {
  page,
  draft,
  pending,
  confirmed,
  working,
  reading,
  readFailed,
  notice,
  storageProblem,
  stale,
  dirty,
  locked,
  unavailable,
  canSave,
} = state;
const packetSearch = ref(page.value.query.q),
  endpointSearch = ref(page.value.query.endpoint_q);
const endpointOffPage = computed(() => {
  const endpoint = draft.value.endpoint;
  return endpoint && !page.value.endpoints.items.some((e) => e.id === endpoint.id);
});
const statusLabels = {
  unconfigured: "Configuration required",
  configured: "Saved configuration",
  active: "Applied",
  outdated: "Changes not applied",
  disabled: "Disabled",
};
function changeEndpoint(event: Event) {
  const id = (event.target as HTMLSelectElement).value;
  state.chooseEndpoint(id ? (page.value.endpoints.items.find((e) => e.id === id) ?? null) : null);
}
</script>
<template>
  <div id="telemetry-packet-bindings-page" class="space-y-5">
    <CadencePageHeading>
      <template #title>Packet bindings</template>
      <template #description>{{ page.spacecraft_name }} · Telemetry Decom</template>
    </CadencePageHeading>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <a
        :href="page.links.manage"
        class="link text-sm"
        @click="state.navigate(page.links.manage, $event)"
        >Manage configuration</a
      >
      <button
        id="refresh-packet-bindings"
        type="button"
        class="btn btn-ghost btn-sm"
        :disabled="working || reading"
        @click="state.refresh"
      >
        {{ reading ? "Refreshing…" : "Refresh saved bindings" }}
      </button>
    </div>
    <div
      v-if="notice"
      id="packet-bindings-notice"
      role="status"
      class="border border-info/30 p-3 text-sm"
    >
      {{ notice }}
    </div>
    <div
      v-if="storageProblem"
      id="packet-bindings-storage-error"
      role="alert"
      class="border border-warning/40 p-3 text-sm text-warning"
    >
      {{ storageProblem }}
    </div>
    <div
      v-if="pending"
      id="packet-bindings-pending"
      role="alert"
      class="space-y-3 border border-warning/40 bg-warning/5 p-4"
    >
      <p class="text-sm">
        This save is awaiting confirmation. Recover its response before changing the draft or
        submitting another save.
      </p>
      <button
        id="recover-packet-save"
        type="button"
        class="btn btn-sm"
        :disabled="working || reading"
        @click="state.recover"
      >
        {{ working ? "Waiting for response…" : "Recover save response" }}
      </button>
    </div>
    <div
      v-if="stale"
      id="packet-bindings-stale"
      role="alert"
      class="space-y-3 border border-warning/40 p-4"
    >
      <p class="text-sm">
        The catalog configuration or saved packet inputs changed. Your draft is retained. Review the
        current saved selection before editing or saving.
      </p>
      <button
        id="review-current-packets"
        type="button"
        class="btn btn-sm"
        :disabled="!!pending || working"
        @click="state.reviewCurrent"
      >
        Review saved selection
      </button>
    </div>
    <div v-if="readFailed" role="alert" class="text-sm text-warning">
      Current evidence is unavailable. Refresh before saving.
    </div>
    <CadenceCard body-class="space-y-5 p-5">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-base font-semibold">
            {{ page.configuration?.catalog_label ?? "Configure a catalog revision" }}
          </h2>
          <p v-if="page.configuration" class="mt-1 text-xs text-base-content/60">
            Revision {{ page.configuration.catalog_version }} · Packet inputs v{{
              page.configuration.version
            }}
          </p>
        </div>
        <span class="border border-base-300 px-2 py-1 text-xs" :data-state="page.status">{{
          statusLabels[page.status]
        }}</span>
      </div>
      <p
        v-if="!page.configuration"
        id="packet-configuration-required"
        class="text-sm text-base-content/70"
      >
        Choose a catalog revision in Manage before saving packet inputs.
      </p>
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <CadenceStatTile
          ><template #label>Saved selection</template>
          <p class="mt-2 font-mono text-xl">{{ page.summary.selected_count }}</p></CadenceStatTile
        >
        <CadenceStatTile
          ><template #label>Draft selection</template>
          <p class="mt-2 font-mono text-xl">{{ draft.ids.length }}</p></CadenceStatTile
        >
        <CadenceStatTile
          ><template #label>Saved scalar fields</template>
          <p class="mt-2 font-mono text-xl">
            {{ page.summary.selected_field_count }}
          </p></CadenceStatTile
        >
      </div>
      <p class="text-sm leading-6 text-base-content/65">
        Each selected packet contributes its compatible scalar fields. APIDs identify traffic; other
        applications may read the same packets. Saving prepares the next governed mission changes
        request.
      </p>
      <div
        v-if="!draft.complete"
        id="packet-selection-incomplete"
        role="alert"
        class="space-y-2 border border-warning/40 p-3 text-sm"
      >
        <p>
          The legacy selection contains {{ page.selection.total_count }} packets. Only 512 can be
          bound at once. Clear the entire draft and make an explicit selection; the saved
          configuration remains unchanged until submission.
        </p>
        <button
          type="button"
          class="btn btn-sm"
          :disabled="locked || stale"
          @click="state.clearSelection"
        >
          Clear entire draft
        </button>
      </div>
      <div
        v-if="unavailable.length"
        id="packet-selection-unavailable"
        role="alert"
        class="space-y-2 border border-warning/40 p-3 text-sm"
      >
        <p>
          {{ unavailable.length }} saved packet selections are unavailable or incompatible in the
          current revision.
        </p>
        <button
          type="button"
          class="btn btn-sm"
          :disabled="locked || stale"
          @click="state.clearUnavailable"
        >
          Remove unavailable selections from draft
        </button>
      </div>
      <section
        aria-labelledby="packet-endpoint-title"
        class="space-y-3 border-t border-base-300/40 pt-5"
      >
        <h2 id="packet-endpoint-title" class="hud-label">Source endpoint</h2>
        <form
          class="flex flex-wrap items-end gap-2"
          @submit.prevent="state.search('endpoint_q', endpointSearch)"
        >
          <CadenceField
            label="Find endpoint"
            wrapper-class="min-w-0 flex-1"
            label-class="mb-1 block text-xs text-base-content/60"
            ><input
              id="packet-endpoint-search"
              v-model="endpointSearch"
              type="search"
              maxlength="128"
              class="input input-bordered w-full"
              :disabled="!!pending || working"
          /></CadenceField>
          <button type="submit" class="btn btn-sm" :disabled="!!pending || working">Find</button>
        </form>
        <CadenceField
          label="Selected source endpoint"
          label-class="mb-1 block text-xs text-base-content/60"
        >
          <select
            id="packet-source-endpoint"
            class="select select-bordered w-full"
            :value="draft.endpoint?.id ?? ''"
            :disabled="locked || stale"
            @change="changeEndpoint"
          >
            <option value="">Choose an endpoint</option>
            <option v-if="endpointOffPage" :value="draft.endpoint!.id">
              {{ draft.endpoint!.label }} (selected)
            </option>
            <option
              v-for="endpoint in page.endpoints.items"
              :key="endpoint.id"
              :value="endpoint.id"
            >
              {{ endpoint.label }}
            </option>
          </select>
        </CadenceField>
        <nav
          aria-label="Endpoint pages"
          class="flex flex-wrap items-center justify-between gap-2 text-xs"
        >
          <a
            v-if="page.endpoints.previous_href"
            :href="page.endpoints.previous_href"
            class="link"
            @click="state.navigate(page.endpoints.previous_href, $event)"
            >Previous endpoints</a
          >
          <span>{{ page.endpoints.total_count }} endpoints · Page {{ page.endpoints.page }}</span>
          <a
            v-if="page.endpoints.next_href"
            :href="page.endpoints.next_href"
            class="link"
            @click="state.navigate(page.endpoints.next_href, $event)"
            >Next endpoints</a
          >
        </nav>
      </section>
      <section
        aria-labelledby="packet-selection-title"
        class="space-y-3 border-t border-base-300/40 pt-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 id="packet-selection-title" class="hud-label">Packet selection</h2>
          <span class="font-mono text-xs text-base-content/60"
            >{{ page.summary.compatible_packet_count }} compatible /
            {{ page.summary.packet_count }} total</span
          >
        </div>
        <form
          class="flex flex-wrap items-end gap-2"
          @submit.prevent="state.search('q', packetSearch)"
        >
          <CadenceField
            label="Find packet by name or APID"
            wrapper-class="min-w-0 flex-1"
            label-class="mb-1 block text-xs text-base-content/60"
            ><input
              id="packet-search"
              v-model="packetSearch"
              type="search"
              maxlength="128"
              class="input input-bordered w-full"
              :disabled="!!pending || working"
          /></CadenceField>
          <button type="submit" class="btn btn-sm" :disabled="!!pending || working">Find</button>
        </form>
        <p
          v-if="!page.packets.items.length"
          id="packet-list-empty"
          class="py-4 text-sm text-base-content/60"
        >
          No packet models match this view.
        </p>
        <ul
          id="packet-selection-list"
          class="divide-y divide-base-300/30 border-y border-base-300/30"
        >
          <li
            v-for="packet in page.packets.items"
            :key="packet.id"
            :data-packet-id="packet.id"
            class="flex items-start gap-3 py-4"
          >
            <input
              :id="`packet-select-${packet.id}`"
              type="checkbox"
              class="checkbox checkbox-sm mt-0.5 shrink-0"
              :checked="draft.ids.includes(packet.id)"
              :disabled="locked || stale || !draft.complete || !packet.selectable"
              @change="state.choosePacket(packet, ($event.target as HTMLInputElement).checked)"
            />
            <div class="min-w-0 flex-1">
              <label
                :for="`packet-select-${packet.id}`"
                class="block font-medium [overflow-wrap:anywhere]"
                >{{ packet.name }}</label
              >
              <p class="mt-1 text-xs text-base-content/60">
                APID {{ packet.apid }} · {{ packet.compatible_field_count }} scalar fields /
                {{ packet.field_count }} total
              </p>
              <p v-if="!packet.selectable" class="mt-1 text-xs text-warning">
                No compatible scalar fields
              </p>
              <a
                :href="packet.detail_href"
                class="link mt-2 inline-block text-xs"
                @click="state.navigate(packet.detail_href, $event)"
                >Inspect packet fields</a
              >
            </div>
          </li>
        </ul>
        <nav
          aria-label="Packet pages"
          class="flex flex-wrap items-center justify-between gap-2 text-xs"
        >
          <a
            v-if="page.packets.previous_href"
            :href="page.packets.previous_href"
            class="link"
            @click="state.navigate(page.packets.previous_href, $event)"
            >Previous packets</a
          >
          <span
            >{{ page.packets.total_count }} matching packets · Page {{ page.packets.page }}</span
          >
          <a
            v-if="page.packets.next_href"
            :href="page.packets.next_href"
            class="link"
            @click="state.navigate(page.packets.next_href, $event)"
            >Next packets</a
          >
        </nav>
      </section>
      <section
        v-if="page.detail"
        id="packet-resource-detail"
        aria-labelledby="packet-resource-title"
        class="space-y-3 border-t border-base-300/40 pt-5"
      >
        <h2 id="packet-resource-title" class="font-semibold [overflow-wrap:anywhere]">
          {{ page.detail.name }}
        </h2>
        <p v-if="!page.detail.available" class="text-sm text-warning">
          This packet is unavailable in the current catalog revision.
        </p>
        <div v-else class="overflow-x-auto">
          <table class="table w-full text-xs">
            <thead>
              <tr>
                <th>Field</th>
                <th>Type</th>
                <th>Bits</th>
                <th>Telemetry</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="resource in page.detail.resources.items" :key="resource.id">
                <td class="font-mono">{{ resource.path }}</td>
                <td>{{ resource.type }}</td>
                <td>{{ resource.size_bits ?? "—" }}</td>
                <td>{{ resource.compatible ? "Accepted" : "Excluded" }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <nav
          aria-label="Resource pages"
          class="flex flex-wrap items-center justify-between gap-2 text-xs"
        >
          <a
            v-if="page.detail.resources.previous_href"
            :href="page.detail.resources.previous_href"
            class="link"
            @click="state.navigate(page.detail.resources.previous_href, $event)"
            >Previous fields</a
          >
          <span
            >{{ page.detail.resources.total_count }} fields · Page
            {{ page.detail.resources.page }}</span
          >
          <a
            v-if="page.detail.resources.next_href"
            :href="page.detail.resources.next_href"
            class="link"
            @click="state.navigate(page.detail.resources.next_href, $event)"
            >Next fields</a
          >
        </nav>
      </section>
      <div
        class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300/40 pt-5"
      >
        <p class="text-xs text-base-content/60">
          {{ dirty ? "Unsaved selection" : "Selection matches saved inputs" }} ·
          {{ draft.ids.length }} / 512 packets
        </p>
        <button
          id="save-packet-bindings"
          type="button"
          class="btn btn-primary btn-sm"
          :disabled="!canSave"
          @click="state.save"
        >
          {{ working ? "Saving…" : "Save packet bindings" }}
        </button>
      </div>
      <p v-if="!draft.ids.length" class="text-xs text-base-content/60">
        Select at least one compatible packet before saving.
      </p>
      <p
        v-if="confirmed"
        id="packet-save-receipt"
        class="text-xs text-base-content/60 [overflow-wrap:anywhere]"
      >
        Last confirmed save: {{ confirmed.receipt.receiptId }} · {{ confirmed.receipt.completedAt }}
      </p>
    </CadenceCard>
  </div>
</template>
