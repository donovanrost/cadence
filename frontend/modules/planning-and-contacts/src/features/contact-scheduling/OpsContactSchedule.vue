<script setup lang="ts">
import { computed, inject } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import {
  CONTACT_SCHEDULE_PORT,
  type OpsContactScheduleProps,
  type SchedulePageKey,
} from "./OpsContactSchedule.contracts";
import { cancellable, scheduleHref, schedulePath } from "./contact-schedule";
import { useContactSchedule } from "./contact-schedule-state";
const props = defineProps<OpsContactScheduleProps>();
const {
  schedule,
  draft,
  pending,
  notice,
  uncertain,
  result,
  receipt,
  cancellation,
  connected,
  refresh,
  search,
  reservable,
  reserve,
  reviewCancel,
  cancel,
} = useContactSchedule(
  () => props.schedule,
  props.port ?? inject(CONTACT_SCHEDULE_PORT, undefined),
);
const pages = computed(() =>
  schedule.value
    ? [
        {
          title: "Spacecraft",
          key: "spacecraft_page" as SchedulePageKey,
          data: schedule.value.spacecraft,
        },
        {
          title: "Ready routes",
          key: "routes_page" as SchedulePageKey,
          data: schedule.value.routes,
        },
        {
          title: "Readiness findings",
          key: "findings_page" as SchedulePageKey,
          data: schedule.value.findings,
        },
        {
          title: "Scheduled contacts",
          key: "scheduled_page" as SchedulePageKey,
          data: schedule.value.scheduled,
        },
        {
          title: "Realized contacts",
          key: "realized_page" as SchedulePageKey,
          data: schedule.value.realized,
        },
        {
          title: "Reservations",
          key: "reservations_page" as SchedulePageKey,
          data: schedule.value.reservations,
        },
      ]
    : [],
);
const label = (v: string) => v.replaceAll("_", " ");
const fieldClass = "w-full rounded border border-base-300 bg-base-100 px-3 py-2 text-sm";
</script>
<template>
  <main v-if="schedule" id="ops-contact-schedule-page" class="min-w-0 space-y-6 p-4 md:p-6">
    <header class="space-y-3">
      <p class="text-xs uppercase tracking-widest text-base-content/60">Planning &amp; contacts</p>
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold">Contact scheduling</h1>
          <p class="mt-1 text-sm text-base-content/70">
            Review route readiness, search provider opportunities, and track contact reservations.
          </p>
        </div>
        <button
          id="contact-schedule-refresh"
          type="button"
          class="rounded border border-base-300 px-4 py-2 text-sm"
          :disabled="pending || !connected"
          @click="refresh"
        >
          {{ pending ? "Working…" : "Refresh ledgers" }}
        </button>
      </div>
      <p
        v-if="notice"
        id="contact-schedule-notice"
        role="status"
        class="rounded border border-base-300 bg-base-200 p-3 text-sm"
      >
        {{ notice }}
      </p>
      <p v-if="uncertain" id="contact-schedule-uncertain" role="alert" class="text-sm text-warning">
        An earlier provider operation needs reconciliation. Refreshing is read-only and does not
        retry that operation.
      </p>
      <p v-if="receipt" id="contact-schedule-receipt" class="break-all text-sm">
        Recorded {{ label(receipt.lifecycleState) }} ·
        <a
          :href="`${schedulePath(schedule.context)}/${encodeURIComponent(receipt.providerReservationId)}`"
          class="text-primary"
          >{{ receipt.providerReservationId }}</a
        >
        · Revision {{ receipt.providerRevision }}
      </p>
    </header>
    <CadencePanel
      id="contact-schedule-spacecraft"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
    >
      <template #header><h2 class="text-lg font-semibold">Choose spacecraft</h2></template>
      <form
        id="contact-spacecraft-filter"
        method="get"
        :action="schedulePath(schedule.context)"
        class="flex flex-wrap items-end gap-3"
      >
        <label class="min-w-0 flex-1 text-sm" for="spacecraft-query"
          >Find spacecraft<input
            id="spacecraft-query"
            name="spacecraft_q"
            type="search"
            maxlength="120"
            :value="schedule.query.spacecraft_q"
            :class="fieldClass"
        /></label>
        <button type="submit" class="rounded border border-base-300 px-4 py-2 text-sm">Find</button>
      </form>
      <p
        v-if="schedule.selected_spacecraft"
        id="contact-selected-spacecraft"
        class="mt-3 break-all text-sm"
      >
        Selected: {{ schedule.selected_spacecraft.name }} · {{ schedule.selected_spacecraft.id }}
      </p>
      <ul class="mt-3 grid gap-2 sm:grid-cols-2">
        <li v-for="craft in schedule.spacecraft.entries" :key="craft.id">
          <a
            :href="
              scheduleHref(schedule, { spacecraft_id: craft.id, routes_page: 1, findings_page: 1 })
            "
            :aria-current="craft.id === schedule.query.spacecraft_id ? 'true' : undefined"
            class="block break-all rounded border border-base-300 p-3 text-sm text-primary"
            >{{ craft.name
            }}<span class="block text-xs text-base-content/60">{{ craft.id }}</span></a
          >
        </li>
      </ul>
      <p v-if="!schedule.spacecraft.entries.length" class="mt-3 text-sm text-base-content/60">
        No spacecraft on this page.
      </p>
    </CadencePanel>
    <CadencePanel
      id="contact-schedule-search"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
    >
      <template #header
        ><h2 class="text-lg font-semibold">Search provider opportunities</h2>
        <p class="mt-1 text-sm text-base-content/60">
          All times are UTC. Each route uses the exact provider, transport, and profile versions
          shown.
        </p></template
      >
      <form
        v-if="schedule.routes.entries.length"
        id="contact-search"
        class="space-y-4"
        @submit.prevent="search"
      >
        <fieldset
          :disabled="pending || uncertain || !connected || !schedule.permissions.operate"
          class="grid gap-4 md:grid-cols-2"
        >
          <label for="contact-route" class="text-sm md:col-span-2"
            >Ready route<select id="contact-route" v-model="draft.route_key" :class="fieldClass">
              <option v-for="route in schedule.routes.entries" :key="route.key" :value="route.key">
                {{ route.provider }} · {{ route.transport }} · {{ route.service }}
              </option>
            </select></label
          >
          <label for="search-start" class="min-w-0 text-sm"
            >Starts at (UTC)<input
              id="search-start"
              v-model="draft.starts_at"
              type="datetime-local"
              step="1"
              required
              :class="fieldClass"
          /></label>
          <label for="search-end" class="min-w-0 text-sm"
            >Ends at (UTC)<input
              id="search-end"
              v-model="draft.ends_at"
              type="datetime-local"
              step="1"
              required
              :class="fieldClass"
          /></label>
          <button
            id="contact-search-submit"
            type="submit"
            class="rounded bg-primary px-4 py-2 text-sm font-medium text-primary-content md:col-span-2"
          >
            Search opportunities
          </button>
        </fieldset>
      </form>
      <p v-else id="contact-no-routes" class="text-sm text-base-content/60">
        {{
          schedule.selected_spacecraft
            ? "No ready routes on this page. Review communications setup or another route page."
            : "Choose a spacecraft to load its ready routes."
        }}
      </p>
      <ul class="mt-4 divide-y divide-base-300 text-sm">
        <li v-for="route in schedule.routes.entries" :key="route.key" class="space-y-1 py-3">
          <p>{{ route.provider }} · {{ route.service }} · {{ route.delivery }}</p>
          <p class="text-base-content/60">{{ route.delivery_summary }}</p>
          <p class="break-all text-xs text-base-content/60">
            Provider {{ route.evidence.provider_id }} v{{ route.evidence.provider_version }} ·
            Transport {{ route.evidence.transport_id }} v{{ route.evidence.transport_version }} ·
            Service v{{ route.evidence.service_profile_ref.version }} · Delivery v{{
              route.evidence.delivery_profile_ref.version
            }}
          </p>
        </li>
      </ul>
      <ul id="contact-readiness-findings" class="space-y-2 text-sm">
        <li
          v-for="finding in schedule.findings.entries"
          :key="`${finding.code}:${finding.resource_id}`"
          class="break-words"
        >
          {{ finding.message
          }}<span v-if="finding.resource_id" class="block break-all text-xs text-base-content/60">{{
            finding.resource_id
          }}</span>
        </li>
      </ul>
      <a
        :href="`/missions/${encodeURIComponent(schedule.context.mission_id)}/comms`"
        class="mt-3 inline-block text-sm text-primary"
        >Review communications setup</a
      >
    </CadencePanel>
    <CadencePanel
      v-if="result"
      id="contact-opportunities"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
    >
      <template #header
        ><h2 class="text-lg font-semibold">
          Provider opportunities · {{ result.opportunities.length }}
        </h2>
        <p class="mt-1 text-sm text-base-content/60">
          {{ result.route.provider }} · {{ result.search.starts_at }} – {{ result.search.ends_at }}
        </p></template
      >
      <ul class="divide-y divide-base-300">
        <li
          v-for="opportunity in result.opportunities"
          :key="opportunity.id"
          class="flex flex-wrap items-center justify-between gap-4 py-4 text-sm"
        >
          <div class="min-w-0 space-y-1">
            <p class="break-all font-medium">{{ opportunity.id }}</p>
            <p>{{ opportunity.starts_at }} – {{ opportunity.ends_at }}</p>
            <p class="break-all text-base-content/60">
              {{ opportunity.station }} · {{ opportunity.antenna ?? "Unspecified antenna" }} ·
              {{ opportunity.availability }}{{ opportunity.synthetic ? " · Synthetic" : "" }}
            </p>
            <p class="text-xs text-base-content/60">
              Expires {{ opportunity.expires_at
              }}<span v-if="opportunity.cost !== null">
                · Provider cost {{ opportunity.cost }}</span
              >
            </p>
          </div>
          <button
            :id="`reserve-${encodeURIComponent(opportunity.id)}`"
            type="button"
            :disabled="!reservable(opportunity)"
            class="rounded border border-base-300 px-4 py-2"
            @click="reserve(opportunity)"
          >
            Reserve
          </button>
        </li>
      </ul>
      <p v-if="result.truncated" id="contact-search-truncated" class="text-sm text-warning">
        Only a bounded portion of the provider results is shown. Narrow the search window to review
        more opportunities.
      </p>
      <p v-if="!result.opportunities.length" class="text-sm text-base-content/60">
        No opportunities in this search window.
      </p>
    </CadencePanel>
    <div class="grid min-w-0 gap-6 lg:grid-cols-2">
      <CadencePanel
        id="contact-scheduled-ledger"
        class="min-w-0 rounded-lg border border-base-300 bg-base-100 p-5"
        header-class="mb-4"
        ><template #header><h2 class="text-lg font-semibold">Scheduled contacts</h2></template>
        <ul class="divide-y divide-base-300 text-sm">
          <li v-for="row in schedule.scheduled.entries" :key="row.id" class="space-y-1 py-3">
            <a
              :href="`${schedulePath(schedule.context)}/records/${encodeURIComponent(row.id)}`"
              class="break-all text-primary"
              >{{ row.id }}</a
            >
            <p>{{ label(row.lifecycle_state) }} · Revision {{ row.revision }}</p>
            <p class="text-xs text-base-content/60">
              {{ row.starts_at ?? "Unrecorded start" }} – {{ row.ends_at ?? "Open-ended" }}
            </p>
            <a
              v-if="row.realized_id"
              :href="`${schedulePath(schedule.context)}/records/${encodeURIComponent(row.realized_id)}`"
              class="text-primary"
              >Realized contact</a
            >
          </li>
        </ul>
        <p v-if="!schedule.scheduled.entries.length" class="text-sm text-base-content/60">
          No scheduled contacts on this page.
        </p>
      </CadencePanel>
      <CadencePanel
        id="contact-realized-ledger"
        class="min-w-0 rounded-lg border border-base-300 bg-base-100 p-5"
        header-class="mb-4"
        ><template #header><h2 class="text-lg font-semibold">Realized contacts</h2></template>
        <ul class="divide-y divide-base-300 text-sm">
          <li v-for="row in schedule.realized.entries" :key="row.id" class="space-y-1 py-3">
            <a
              :href="`${schedulePath(schedule.context)}/records/${encodeURIComponent(row.id)}`"
              class="break-all text-primary"
              >{{ row.id }}</a
            >
            <p>{{ label(row.lifecycle_state) }} · {{ row.clock_mode }}</p>
            <p class="text-xs text-base-content/60">
              {{ row.realized_at ?? "No realization timestamp" }}
            </p>
          </li>
        </ul>
        <p v-if="!schedule.realized.entries.length" class="text-sm text-base-content/60">
          No realized contacts on this page.
        </p>
      </CadencePanel>
    </div>
    <CadencePanel
      id="contact-reservations"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
      ><template #header><h2 class="text-lg font-semibold">Provider reservations</h2></template>
      <ul class="divide-y divide-base-300 text-sm">
        <li v-for="row in schedule.reservations.entries" :key="row.id" class="space-y-2 py-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <a
              :href="`${schedulePath(schedule.context)}/${encodeURIComponent(row.id)}`"
              class="break-all text-primary"
              >{{ row.id }}</a
            ><button
              v-if="schedule.permissions.cancel && cancellable(row)"
              :id="`cancel-review-${encodeURIComponent(row.id)}`"
              type="button"
              :disabled="pending || uncertain || !connected"
              class="rounded border border-base-300 px-3 py-2"
              @click="reviewCancel(row)"
            >
              Review cancellation
            </button>
          </div>
          <p>{{ label(row.lifecycle_state) }} · Provider revision {{ row.provider_revision }}</p>
          <p>{{ row.starts_at }} – {{ row.ends_at }}</p>
          <p class="break-all text-xs text-base-content/60">
            {{ row.provider_id }} v{{ row.provider_version }} ·
            {{ row.provider_contact_ref ?? "Awaiting provider reference" }}
          </p>
          <p
            v-if="['unknown', 'canceling', 'requesting'].includes(row.lifecycle_state)"
            class="text-warning"
          >
            Provider outcome needs reconciliation. Review the reservation evidence.
          </p>
          <a
            v-if="row.scheduled_id"
            :href="`${schedulePath(schedule.context)}/records/${encodeURIComponent(row.scheduled_id)}`"
            class="text-primary"
            >Scheduled contact</a
          >
        </li>
      </ul>
      <p v-if="!schedule.reservations.entries.length" class="text-sm text-base-content/60">
        No reservations on this page.
      </p>
      <div
        v-if="cancellation"
        id="contact-cancellation-review"
        class="mt-4 space-y-3 rounded border border-warning p-4 text-sm"
      >
        <h3 class="font-semibold">Confirm provider cancellation</h3>
        <p class="break-all">{{ cancellation.id }} · {{ cancellation.provider_contact_ref }}</p>
        <p>
          Reviewed revision {{ cancellation.provider_revision }} ·
          {{ label(cancellation.lifecycle_state) }} · {{ cancellation.starts_at }} –
          {{ cancellation.ends_at }}
        </p>
        <p>
          This asks the provider to cancel the reservation. A changed reservation must be reviewed
          again.
        </p>
        <div class="flex gap-3">
          <button
            id="contact-cancel-confirm"
            type="button"
            :disabled="pending || uncertain || !connected"
            class="rounded border border-warning px-4 py-2"
            @click="cancel"
          >
            Confirm cancellation</button
          ><button
            id="contact-cancel-dismiss"
            type="button"
            :disabled="pending"
            @click="cancellation = null"
          >
            Keep reservation
          </button>
        </div>
      </div>
    </CadencePanel>
    <nav
      aria-label="Contact scheduling pages"
      class="grid gap-3 rounded border border-base-300 p-4 text-sm sm:grid-cols-2 lg:grid-cols-3"
    >
      <div v-for="page in pages" :key="page.key" class="space-y-2">
        <p class="font-medium">{{ page.title }} · Page {{ page.data.page }}</p>
        <div class="flex gap-4 text-primary">
          <a
            v-if="page.data.page > 1"
            :id="`${page.key}-previous`"
            :href="scheduleHref(schedule, { [page.key]: page.data.page - 1 })"
            >Previous</a
          ><a
            v-if="page.data.more"
            :id="`${page.key}-next`"
            :href="scheduleHref(schedule, { [page.key]: page.data.page + 1 })"
            >Next</a
          >
        </div>
      </div>
    </nav>
  </main>
  <div v-else id="contact-schedule-unavailable" role="alert" class="space-y-3 p-6">
    <h1 class="text-lg font-semibold">Contact scheduling unavailable</h1>
    <p v-if="notice">{{ notice }}</p>
    <button
      id="contact-schedule-retry"
      type="button"
      :disabled="pending || !connected"
      @click="refresh"
    >
      Refresh evidence
    </button>
  </div>
</template>
