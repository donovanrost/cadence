<script setup lang="ts">
import { inject } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import {
  RESERVATION_PORT,
  type OpsContactDetailProps,
  type ReservationAction,
} from "./OpsContactDetail.contracts";
import { reservationHref, canDecide } from "./reservation-detail";
import { useReservation } from "./reservation-state";
const props = defineProps<OpsContactDetailProps>();
const state = useReservation(() => props.detail, props.port ?? inject(RESERVATION_PORT, undefined));
const {
  detail,
  reasons,
  pending,
  locked,
  notice,
  enabled,
  execute,
  refresh,
  connected,
  confirmed,
} = state;
const actions: { id: ReservationAction; label: string }[] = [
  { id: "approve-provider-change", label: "Approve change" },
  { id: "reject-provider-change", label: "Reject change" },
  { id: "acknowledge-provider-change", label: "Acknowledge change" },
];
const label = (value: string) => value.replaceAll("_", " ");
</script>
<template>
  <main v-if="detail" id="ops-contact-detail-page" class="space-y-6 p-4 md:p-6">
    <header class="space-y-3">
      <a
        :href="`/missions/${encodeURIComponent(detail.context.mission_id)}/ops/contacts`"
        class="text-sm text-primary"
        >Contact scheduling</a
      >
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p class="text-xs uppercase tracking-widest text-base-content/60">
            Planning &amp; contacts
          </p>
          <h1 class="text-2xl font-semibold">Reservation review</h1>
          <p class="break-all text-sm text-base-content/70">{{ detail.reservation.id }}</p>
        </div>
        <button
          id="reservation-refresh"
          type="button"
          class="rounded border border-base-300 px-4 py-2 text-sm"
          :disabled="pending || !connected"
          @click="refresh"
        >
          {{ pending ? "Working…" : "Refresh evidence" }}
        </button>
      </div>
      <p id="reservation-current-state" class="text-sm">
        {{ label(detail.reservation.lifecycle_state) }} · Provider revision
        {{ detail.reservation.provider_revision }} · {{ detail.reservation.starts_at }} –
        {{ detail.reservation.ends_at }}
      </p>
      <p
        v-if="notice"
        id="reservation-notice"
        role="status"
        class="rounded border border-base-300 bg-base-200 p-3 text-sm"
      >
        {{ notice }}
      </p>
      <p v-if="confirmed?.receipt" id="reservation-receipt" class="break-all text-sm">
        Recorded {{ label(confirmed.receipt.result.value.lifecycleState) }} ·
        {{ confirmed.receipt.result.value.providerReservationChangeId }} ·
        {{ confirmed.receipt.completedAt }}
      </p>
    </header>
    <CadencePanel class="rounded-lg border border-base-300 bg-base-100 p-5" header-class="mb-4">
      <template #header><h2 class="text-lg font-semibold">Reviewed provider change</h2></template>
      <div v-if="detail.selected" class="space-y-4">
        <p id="reservation-reviewed-revision">
          Revision {{ detail.selected.from_provider_revision }} →
          {{ detail.selected.provider_revision }} · {{ label(detail.selected.lifecycle_state) }} ·
          Policy {{ detail.selected.policy_version }}
        </p>
        <p class="text-sm text-base-content/70">
          {{ label(detail.selected.classification) }} · Recorded {{ detail.selected.recorded_at }}
        </p>
        <p id="reservation-reviewed-hash" class="break-all font-mono text-xs">
          {{ detail.selected.proposal_hash }}
        </p>
        <p v-if="detail.selected.deadline_at" class="text-sm">
          Decision deadline: {{ detail.selected.deadline_at }}
        </p>
        <p
          v-if="detail.selected.provider_revision !== detail.reservation.provider_revision"
          id="reservation-historical"
          class="text-sm"
        >
          Historical provider change. Decisions are disabled.
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead>
              <tr class="border-b border-base-300">
                <th class="p-2">Changed field</th>
                <th class="p-2">Before</th>
                <th class="p-2">After</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(field, index) in detail.selected.fields"
                :key="index"
                class="border-b border-base-300/50"
              >
                <th class="p-2 font-medium">{{ label(field.field) }}</th>
                <td class="max-w-xs break-words p-2">{{ field.before }}</td>
                <td class="max-w-xs break-words p-2">{{ field.after }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-if="!detail.selected.review_complete" id="reservation-restricted" class="text-sm">
          This change includes restricted provider data. Approval and rejection require a complete
          review outside this surface.
        </p>
        <p v-if="!detail.permissions.decide" id="reservation-admin-required" class="text-sm">
          An organization administrator must record this decision.
        </p>
        <p v-if="locked" class="text-sm">
          Further decisions are disabled until the completed operation is reconciled.
        </p>
        <div class="grid gap-4 lg:grid-cols-3">
          <form
            v-for="action in actions.filter((a) => canDecide(detail!, a.id))"
            :id="`${action.id}-form`"
            :key="action.id"
            class="space-y-2 rounded border border-base-300 p-4"
            @submit.prevent="execute(action.id, reasons[action.id])"
          >
            <label :for="`${action.id}-reason`" class="block text-sm font-medium"
              >{{ action.label }} — reason</label
            >
            <textarea
              :id="`${action.id}-reason`"
              v-model="reasons[action.id]"
              required
              maxlength="4096"
              :disabled="pending"
              class="w-full rounded border border-base-300 bg-base-100 p-2"
            />
            <button
              :id="action.id"
              type="submit"
              :disabled="!enabled(action.id)"
              class="rounded bg-primary px-4 py-2 text-sm text-primary-content"
            >
              {{ action.label }}
            </button>
          </form>
        </div>
      </div>
      <p v-else id="reservation-no-changes" class="text-sm text-base-content/70">
        No provider changes have been recorded.
      </p>
    </CadencePanel>
    <CadencePanel class="rounded-lg border border-base-300 bg-base-100 p-5" header-class="mb-4">
      <template #header
        ><h2 class="text-lg font-semibold">
          Requested, provider-confirmed, and accepted values
        </h2></template
      >
      <div class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead>
            <tr class="border-b border-base-300">
              <th class="p-2">Field</th>
              <th class="p-2">Requested</th>
              <th class="p-2">Provider-confirmed</th>
              <th class="p-2">Cadence-accepted</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in detail.values" :key="row.field" class="border-b border-base-300/50">
              <th class="p-2 font-medium">{{ label(row.field) }}</th>
              <td class="max-w-xs break-words p-2">{{ row.requested }}</td>
              <td class="max-w-xs break-words p-2">{{ row.confirmed }}</td>
              <td class="max-w-xs break-words p-2">{{ row.accepted }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </CadencePanel>
    <CadencePanel class="rounded-lg border border-base-300 bg-base-100 p-5" header-class="mb-4">
      <template #header><h2 class="text-lg font-semibold">Reservation bindings</h2></template>
      <dl class="grid gap-4 text-sm md:grid-cols-2">
        <div>
          <dt class="text-base-content/60">Provider</dt>
          <dd class="break-all">
            {{ detail.reservation.provider_id }} · Version {{ detail.reservation.provider_version }}
          </dd>
        </div>
        <div>
          <dt class="text-base-content/60">Spacecraft</dt>
          <dd class="break-all">{{ detail.reservation.spacecraft_id }}</dd>
        </div>
        <div>
          <dt class="text-base-content/60">Scheduled contact</dt>
          <dd class="break-all">{{ detail.reservation.scheduled_contact_id }}</dd>
        </div>
        <div v-if="detail.reservation.transport_id">
          <dt class="text-base-content/60">Transport</dt>
          <dd class="break-all">
            {{ detail.reservation.transport_id }} · Version
            {{ detail.reservation.transport_version }}
          </dd>
        </div>
        <div v-if="detail.reservation.plan_id">
          <dt class="text-base-content/60">Contact plan</dt>
          <dd>
            <a
              id="reservation-plan"
              class="text-primary"
              :href="`/missions/${encodeURIComponent(detail.context.mission_id)}/ops/plans/${encodeURIComponent(detail.reservation.plan_id)}?version=${detail.reservation.plan_version}`"
              >{{ detail.reservation.plan_id }} · Version {{ detail.reservation.plan_version }}</a
            >
          </dd>
        </div>
        <div v-if="detail.reservation.requirement_id">
          <dt class="text-base-content/60">Contact requirement</dt>
          <dd>
            <a
              id="reservation-requirement"
              class="text-primary"
              :href="`/missions/${encodeURIComponent(detail.context.mission_id)}/ops/requirements/${encodeURIComponent(detail.reservation.requirement_id)}?version=${detail.reservation.requirement_version}`"
              >{{ detail.reservation.requirement_id }} · Version
              {{ detail.reservation.requirement_version }}</a
            >
          </dd>
        </div>
      </dl>
    </CadencePanel>
    <div class="grid gap-6 lg:grid-cols-2">
      <CadencePanel class="rounded-lg border border-base-300 bg-base-100 p-5" header-class="mb-4"
        ><template #header><h2 class="text-lg font-semibold">Provider change history</h2></template>
        <ol id="reservation-change-history" class="divide-y divide-base-300">
          <li v-for="change in detail.changes.entries" :key="change.id" class="py-3 text-sm">
            <a
              :href="reservationHref(detail, { change_id: change.id })"
              class="text-primary"
              :aria-current="change.id === detail.selected?.id ? 'page' : undefined"
              >Revision {{ change.provider_revision }} · {{ label(change.lifecycle_state) }}</a
            >
            <p class="text-xs text-base-content/60">{{ change.recorded_at }}</p>
          </li>
        </ol>
        <nav
          aria-label="Provider change history pages"
          class="mt-4 flex gap-4 text-sm text-primary"
        >
          <a
            v-if="detail.query.before_revision"
            id="changes-latest"
            :href="reservationHref(detail, { before_revision: null })"
            >Latest changes</a
          ><a
            v-if="detail.changes.next"
            id="changes-older"
            :href="reservationHref(detail, { before_revision: detail.changes.next })"
            >Older changes</a
          >
        </nav>
      </CadencePanel>
      <CadencePanel class="rounded-lg border border-base-300 bg-base-100 p-5" header-class="mb-4"
        ><template #header><h2 class="text-lg font-semibold">Reservation audit</h2></template>
        <ol id="reservation-audit" class="divide-y divide-base-300">
          <li v-for="entry in detail.audit.entries" :key="entry.id" class="py-3 text-sm">
            <p>{{ entry.action }} · {{ entry.outcome }}</p>
            <p class="text-xs text-base-content/60">{{ entry.recorded_at }}</p>
            <a
              v-if="entry.change_id"
              :href="reservationHref(detail, { change_id: entry.change_id })"
              class="text-primary"
              >Review change</a
            >
          </li>
        </ol>
        <p
          v-if="!detail.audit.entries.length"
          id="reservation-no-audit"
          class="text-sm text-base-content/70"
        >
          No audit entries on this page.
        </p>
        <nav aria-label="Reservation audit pages" class="mt-4 flex gap-4 text-sm text-primary">
          <a
            v-if="detail.query.before_audit"
            id="audit-latest"
            :href="reservationHref(detail, { before_audit: null })"
            >Latest audit</a
          ><a
            v-if="detail.audit.next"
            id="audit-older"
            :href="reservationHref(detail, { before_audit: detail.audit.next })"
            >Older audit</a
          >
        </nav>
      </CadencePanel>
    </div>
  </main>
  <div v-else id="reservation-unavailable" role="alert" class="space-y-3 p-6">
    <p>Reservation review is unavailable.</p>
    <button id="reservation-retry" type="button" :disabled="pending || !connected" @click="refresh">
      Refresh evidence
    </button>
  </div>
</template>
