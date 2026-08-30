<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk";
import { CButton, CCheckbox, CStatePanel, CStatus } from "@cadence/ui";
import { computed, onMounted, ref } from "vue";
import { filterPackets, type PacketBindingsData, type SavePacketBindingsResult } from "./telemetry";

const props = defineProps<FederatedApplicationProps>();
const frontendRelease = __CADENCE_REMOTE_RELEASE__;

const data = ref<PacketBindingsData>();
const loading = ref(true);
const saving = ref(false);
const error = ref<string>();
const notice = ref<string>();
const search = ref("");
const selectedOnly = ref(false);
const selectedApids = ref(new Set<number>());
const persistedApids = ref(new Set<number>());

const visiblePackets = computed(() =>
  filterPackets(data.value?.packets ?? [], search.value, selectedOnly.value, selectedApids.value),
);

const dirty = computed(() => !sameSet(selectedApids.value, persistedApids.value));
const selectedCount = computed(() => selectedApids.value.size);
const totalRate = computed(() =>
  (data.value?.packets ?? [])
    .filter(({ apid }) => selectedApids.value.has(apid))
    .reduce((sum, packet) => sum + packet.rateHz, 0),
);

onMounted(loadPacketBindings);

async function loadPacketBindings(): Promise<void> {
  loading.value = true;
  error.value = undefined;

  try {
    const response = await props.bridge.query<PacketBindingsData>({
      queryId: "cadence.packet_bindings.manage",
      version: 1,
      context: props.context,
    });
    data.value = response;
    const initialSelection = new Set(
      response.packets.filter(({ selected }) => selected).map(({ apid }) => apid),
    );
    selectedApids.value = new Set(initialSelection);
    persistedApids.value = initialSelection;
  } catch (reason) {
    error.value = messageFor(reason, "Packet bindings could not be loaded.");
  } finally {
    loading.value = false;
  }
}

function setPacketSelection(apid: number, selected: boolean): void {
  const next = new Set(selectedApids.value);
  if (selected) next.add(apid);
  else next.delete(apid);
  selectedApids.value = next;
  notice.value = undefined;
}

function selectVisible(): void {
  const next = new Set(selectedApids.value);
  for (const packet of visiblePackets.value) next.add(packet.apid);
  selectedApids.value = next;
  notice.value = undefined;
}

function resetDraft(): void {
  selectedApids.value = new Set(persistedApids.value);
  notice.value = "Draft reset to the host configuration.";
}

async function saveBindings(): Promise<void> {
  if (!data.value || !dirty.value) return;
  saving.value = true;
  error.value = undefined;
  notice.value = undefined;

  try {
    const receipt = await props.bridge.execute<
      { expectedConfigurationVersion: number; selectedApids: number[] },
      SavePacketBindingsResult
    >({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      input: {
        expectedConfigurationVersion: data.value.configurationVersion,
        selectedApids: [...selectedApids.value].sort((left, right) => left - right),
      },
      context: props.context,
    });

    data.value.configurationVersion = receipt.result.configurationVersion;
    persistedApids.value = new Set(selectedApids.value);
    notice.value = `Bindings saved · receipt ${receipt.receiptId.slice(-8)}`;
  } catch (reason) {
    error.value = messageFor(reason, "Packet bindings could not be saved.");
  } finally {
    saving.value = false;
  }
}

function rateLabel(rateHz: number): string {
  return rateHz < 1 ? `${rateHz.toFixed(1)} Hz` : `${rateHz} Hz`;
}

function sameSet(left: ReadonlySet<number>, right: ReadonlySet<number>): boolean {
  return left.size === right.size && [...left].every((value) => right.has(value));
}

function messageFor(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}
</script>

<template>
  <div class="decom-app">
    <CStatePanel
      v-if="loading"
      id="packet-bindings-loading"
      class="decom-state"
      title="Acquiring packet catalog"
      :description="`Querying the host contract for ${context.spacecraftName}.`"
      tone="loading"
    />

    <CStatePanel
      v-else-if="!data"
      id="packet-bindings-error"
      class="decom-state"
      title="Packet catalog unavailable"
      tone="error"
    >
      <p>{{ error }}</p>
      <template #action>
        <CButton id="retry-packet-bindings" size="sm" @click="loadPacketBindings">
          Retry host query
        </CButton>
      </template>
    </CStatePanel>

    <template v-else>
      <section class="decom-overview" aria-labelledby="decom-overview-title">
        <div>
          <p class="decom-kicker">SPACECRAFT INPUT CONFIGURATION · {{ frontendRelease }}</p>
          <h2 id="decom-overview-title">Choose packets to decommutate</h2>
          <p class="decom-intro">
            Build the active decode set from the imported XTCE revision. Changes stay local until
            the host accepts a save action.
          </p>
        </div>
        <div class="decom-summary">
          <div>
            <span>SELECTED</span>
            <strong
              >{{ selectedCount }}<small>/{{ data.packets.length }}</small></strong
            >
          </div>
          <div>
            <span>COMBINED RATE</span>
            <strong>{{ totalRate.toFixed(1) }}<small> Hz</small></strong>
          </div>
        </div>
      </section>

      <section class="source-strip" aria-label="Packet binding source">
        <div class="source-strip__item">
          <span>DEFINITION REVISION</span>
          <strong>{{ data.revision.label }}</strong>
          <small>Imported 22 Aug · 14:32Z</small>
        </div>
        <div class="source-strip__item">
          <span>SOURCE ENDPOINT</span>
          <CStatus tone="nominal" pulse>
            <strong>{{ data.sourceEndpoint.label }}</strong>
          </CStatus>
          <small>{{ data.sourceEndpoint.status }}</small>
        </div>
        <div class="source-strip__item">
          <span>CONFIG VERSION</span>
          <strong>v{{ data.configurationVersion }}</strong>
          <small>Optimistic concurrency</small>
        </div>
      </section>

      <section class="packet-workspace" aria-labelledby="packet-catalog-title">
        <div class="packet-toolbar">
          <label class="packet-search" for="packet-search">
            <span aria-hidden="true"></span>
            <input
              id="packet-search"
              v-model="search"
              type="search"
              placeholder="Filter by APID, name, or field…"
              autocomplete="off"
            />
            <kbd>/</kbd>
          </label>

          <CCheckbox id="selected-only" v-model="selectedOnly" class="selected-filter">
            <span>Selected only</span>
          </CCheckbox>

          <CButton id="select-visible" @click="selectVisible">Select visible</CButton>
        </div>

        <div class="packet-table-head" aria-hidden="true">
          <span></span>
          <span id="packet-catalog-title">APID / PACKET</span>
          <span>FIELDS</span>
          <span>RATE</span>
          <span>INPUT</span>
        </div>

        <div id="packet-catalog" class="packet-list">
          <CCheckbox
            v-for="packet in visiblePackets"
            :key="packet.apid"
            :id="`packet-${packet.apid}`"
            class="packet-row"
            presentation="row"
            :model-value="selectedApids.has(packet.apid)"
            @update:model-value="setPacketSelection(packet.apid, $event)"
          >
            <span class="packet-row__identity">
              <b>{{ String(packet.apid).padStart(3, "0") }}</b>
              <span>
                <strong>{{ packet.name }}</strong>
                <small>{{ packet.description }}</small>
              </span>
            </span>
            <span class="packet-row__metric">{{ packet.fieldCount }}</span>
            <span class="packet-row__metric">{{ rateLabel(packet.rateHz) }}</span>
            <span class="packet-row__state">
              {{ selectedApids.has(packet.apid) ? "ACTIVE" : "STANDBY" }}
            </span>
          </CCheckbox>

          <div v-if="visiblePackets.length === 0" id="packet-catalog-empty" class="packet-empty">
            No packets match this local filter.
          </div>
        </div>
      </section>

      <div
        v-if="error || notice"
        id="packet-bindings-message"
        :class="['decom-message', { 'decom-message--error': error }]"
      >
        {{ error ?? notice }}
      </div>

      <footer class="decom-actions">
        <CStatus :tone="dirty ? 'warning' : 'nominal'" :pulse="dirty">
          {{ dirty ? "Unsaved local changes" : "Configuration synchronized" }}
        </CStatus>
        <CButton id="reset-packet-bindings" :disabled="!dirty || saving" @click="resetDraft">
          Reset
        </CButton>
        <CButton
          id="save-packet-bindings"
          :disabled="!dirty || saving"
          :loading="saving"
          variant="primary"
          @click="saveBindings"
        >
          {{ saving ? "Authorizing…" : "Save bindings" }}
        </CButton>
      </footer>
    </template>
  </div>
</template>

<style scoped>
.decom-app {
  min-height: 467px;
  color: var(--cadence-color-text);
  background: var(--cadence-color-surface-inset);
  font-family: var(--cadence-font-sans);
}

.decom-state {
  min-height: 467px;
}

.decom-state p {
  margin: 0;
  font-size: 13px;
}

.decom-overview {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 36px;
  padding: 28px 30px 25px;
}

.decom-kicker,
.source-strip span,
.packet-table-head,
.decom-summary span,
.packet-row__state {
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  font-weight: 620;
  letter-spacing: 0.105em;
}

.decom-kicker {
  margin: 0 0 8px;
  color: var(--cadence-color-accent);
}

.decom-overview h2 {
  margin: 0;
  color: #edf0ed;
  font-size: clamp(23px, 3vw, 31px);
  font-weight: 580;
  letter-spacing: -0.03em;
}

.decom-intro {
  max-width: 620px;
  margin: 9px 0 0;
  color: var(--cadence-color-text-secondary);
  font-size: 13px;
  line-height: 1.5;
}

.decom-summary {
  display: flex;
  min-width: max-content;
  border: 1px solid var(--cadence-color-border);
}

.decom-summary > div {
  display: grid;
  gap: 5px;
  min-width: 110px;
  padding: 12px 14px;
}

.decom-summary > div + div {
  border-left: 1px solid var(--cadence-color-border);
}

.decom-summary span {
  color: var(--cadence-color-text-muted);
}

.decom-summary strong {
  color: var(--cadence-color-signal);
  font-family: var(--cadence-font-mono);
  font-size: 19px;
  font-weight: 560;
}

.decom-summary small {
  color: #708082;
  font-size: 10px;
}

.source-strip {
  display: grid;
  grid-template-columns: 1.4fr 1fr 0.8fr;
  border-top: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
  background: #151e1f;
}

.source-strip__item {
  display: grid;
  gap: 5px;
  padding: 13px 18px;
}

.source-strip__item + .source-strip__item {
  border-left: 1px solid var(--cadence-color-border);
}

.source-strip span {
  color: var(--cadence-color-text-muted);
}

.source-strip strong {
  color: #c7cfcd;
  font-family: var(--cadence-font-mono);
  font-size: 11px;
  font-weight: 530;
}

.source-strip small {
  color: var(--cadence-color-text-muted);
  font-size: 10px;
  text-transform: capitalize;
}

.packet-workspace {
  padding: 22px 30px 0;
}

.packet-toolbar {
  display: flex;
  gap: 9px;
  margin-bottom: 13px;
}

.packet-search {
  position: relative;
  display: flex;
  flex: 1;
  align-items: center;
  min-width: 180px;
}

.packet-search > span {
  position: absolute;
  left: 13px;
  width: 11px;
  height: 11px;
  border: 1px solid #758285;
  border-radius: 50%;
}

.packet-search > span::after {
  position: absolute;
  right: -4px;
  bottom: -3px;
  width: 5px;
  height: 1px;
  background: #758285;
  content: "";
  transform: rotate(45deg);
}

.packet-search input {
  width: 100%;
  height: 38px;
  padding: 0 40px 0 35px;
  border: 1px solid #3a4648;
  border-radius: 0;
  color: var(--cadence-color-text);
  background: #101617;
  font-size: 12px;
}

.packet-search input::placeholder {
  color: #596568;
}

.packet-search kbd {
  position: absolute;
  right: 10px;
  padding: 2px 6px;
  border: 1px solid #344042;
  color: #596568;
  background: #172022;
  font-family: var(--cadence-font-mono);
  font-size: 9px;
}

.selected-filter {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 38px;
  padding: 0 12px;
  border: 1px solid #3a4648;
  color: #98a3a2;
  background: #182022;
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  text-transform: uppercase;
  cursor: pointer;
}

.packet-table-head,
.packet-row {
  display: grid;
  grid-template-columns: 24px minmax(250px, 1fr) 65px 72px 70px;
  align-items: center;
  gap: 12px;
}

.packet-table-head {
  min-height: 27px;
  padding: 0 12px;
  border-bottom: 1px solid #394547;
  color: #596669;
}

.packet-list {
  border-bottom: 1px solid var(--cadence-color-border);
}

.packet-row {
  position: relative;
  min-height: 63px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--cadence-color-border-subtle);
  background: #12191a;
  cursor: pointer;
  transition: 120ms ease;
}

.packet-row:last-child {
  border-bottom: 0;
}

.packet-row:hover {
  background: #172022;
}

.packet-row[data-state="checked"] {
  background: linear-gradient(90deg, rgba(245, 166, 35, 0.075), transparent 45%);
}

.packet-row[data-state="checked"]::before {
  position: absolute;
  top: 0;
  bottom: 0;
  left: 0;
  width: 2px;
  background: var(--cadence-color-accent);
  content: "";
}

.packet-row__identity {
  display: grid;
  grid-template-columns: 36px minmax(0, 1fr);
  align-items: center;
  gap: 12px;
  min-width: 0;
}

.packet-row__identity > b {
  color: var(--cadence-color-accent);
  font-family: var(--cadence-font-mono);
  font-size: 12px;
  font-weight: 560;
}

.packet-row__identity > span {
  display: grid;
  min-width: 0;
}

.packet-row__identity strong {
  overflow: hidden;
  color: #cbd2d0;
  font-size: 12px;
  font-weight: 620;
  letter-spacing: 0.025em;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.packet-row__identity small {
  overflow: hidden;
  margin-top: 3px;
  color: #667376;
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.packet-row__metric {
  color: #8c9899;
  font-family: var(--cadence-font-mono);
  font-size: 10px;
}

.packet-row__state {
  color: #536063;
}

.packet-row[data-state="checked"] .packet-row__state {
  color: var(--cadence-color-signal);
}

.packet-empty {
  padding: 36px 18px;
  color: #637073;
  font-family: var(--cadence-font-mono);
  font-size: 11px;
  text-align: center;
}

.decom-message {
  margin: 15px 30px 0;
  padding: 9px 12px;
  border: 1px solid #2a4e4a;
  color: var(--cadence-color-signal);
  background: #12201f;
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  text-transform: uppercase;
}

.decom-message--error {
  border-color: #613c36;
  color: var(--cadence-color-danger);
  background: #241817;
}

.decom-actions {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 17px 30px 22px;
}

.decom-actions > .cui-status {
  display: flex;
  flex: 1;
  align-items: center;
  gap: 8px;
  color: #687577;
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  text-transform: uppercase;
}

.decom-actions > .cui-button:last-child {
  min-width: 124px;
}

@media (max-width: 900px) {
  .decom-overview {
    align-items: flex-start;
    flex-direction: column;
  }

  .source-strip {
    grid-template-columns: 1fr;
  }

  .source-strip__item + .source-strip__item {
    border-top: 1px solid var(--cadence-color-border);
    border-left: 0;
  }

  .packet-toolbar {
    flex-wrap: wrap;
  }

  .packet-search {
    flex-basis: 100%;
  }

  .packet-table-head,
  .packet-row {
    grid-template-columns: 24px minmax(160px, 1fr) 62px 68px;
  }

  .packet-table-head span:nth-child(3),
  .packet-row__metric:first-of-type {
    display: none;
  }

  .packet-table-head span:last-child,
  .packet-row__state {
    display: none;
  }
}

@media (max-width: 560px) {
  .decom-overview,
  .packet-workspace,
  .decom-actions {
    padding-right: 16px;
    padding-left: 16px;
  }

  .decom-summary {
    width: 100%;
  }

  .decom-summary > div {
    flex: 1;
    min-width: 0;
  }

  .selected-filter,
  #select-visible {
    flex: 1;
    justify-content: center;
  }

  .packet-table-head,
  .packet-row {
    grid-template-columns: 24px minmax(130px, 1fr) 62px;
  }

  .packet-table-head span:nth-child(4),
  .packet-row__metric:last-of-type {
    display: none;
  }

  .decom-actions {
    flex-wrap: wrap;
  }

  .decom-actions > .cui-status {
    flex-basis: 100%;
  }

  .decom-actions > .cui-button {
    flex: 1;
  }
}
</style>
