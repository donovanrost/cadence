<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import ConfigurationOverview from "./ConfigurationOverview.vue";
import CatalogApplications from "./CatalogApplications.vue";
import ConfigurationInspector from "./ConfigurationInspector.vue";
import CommunicationsSetup from "./CommunicationsSetup.vue";
import ConfigurationChanges from "./ConfigurationChanges.vue";
import CommandingHandoff from "./CommandingHandoff.vue";
import SpacecraftSwitcher from "./SpacecraftSwitcher.vue";
import {
  configurationChanges,
  fleet,
  sections,
  type Inspector,
  type RevisionId,
  type SetupIssue,
} from "./fixtures";
import type { useSpacecraftStudy } from "./state";
import "./spacecraft-study.css";

const props = withDefaults(
  defineProps<{ study: ReturnType<typeof useSpacecraftStudy>; standalone?: boolean }>(),
  { standalone: false },
);
const {
  spacecraft,
  selectedId,
  section,
  inspector,
  feedback,
  current,
  identity,
  draft,
  changes,
  unsaved,
  issues,
  canReview,
  canActivate,
  canOpenOps,
  selectSpacecraft,
  navigate,
  edit,
  saveDraft,
  discardUnsaved,
  submitReview,
  simulateApproval,
  activate,
  applyPreset,
} = props.study;
const root = ref<HTMLElement | null>(null);
const headingActions = ref<HTMLElement | null>(null);
const fleetNavigation = ref<HTMLElement | null>(null);
let inspectorTrigger: HTMLElement | null = null;
let fleetObserver: ResizeObserver | null = null;
const activeCount = computed(() => fleet.filter((craft) => spacecraft[craft.id].active).length);

function revealSelectedSpacecraft() {
  const navigation = fleetNavigation.value;
  if (!navigation || navigation.scrollWidth <= navigation.clientWidth) return;
  navigation
    .querySelector<HTMLElement>('[aria-pressed="true"]')
    ?.scrollIntoView({ block: "nearest", inline: "nearest" });
}
onMounted(() => {
  fleetObserver = new ResizeObserver(revealSelectedSpacecraft);
  if (fleetNavigation.value) fleetObserver.observe(fleetNavigation.value);
});
onBeforeUnmount(() => fleetObserver?.disconnect());
watch(selectedId, revealSelectedSpacecraft, { flush: "post" });

async function openInspector(kind: Inspector, event: MouseEvent) {
  inspectorTrigger = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
  inspector.value = kind;
  await nextTick();
  root.value?.querySelector<HTMLElement>("#sc-inspector-title")?.focus();
}
async function closeInspector() {
  if (!inspector.value) return;
  inspector.value = null;
  await nextTick();
  if (inspectorTrigger?.isConnected) inspectorTrigger.focus();
  else root.value?.querySelector<HTMLElement>('[aria-current="page"]')?.focus();
}
async function chooseRevision(revision: RevisionId) {
  edit({ catalog: revision });
  await closeInspector();
}
async function repair(issue: SetupIssue, event: MouseEvent) {
  navigate(issue.section);
  if (issue.inspector) await openInspector(issue.inspector, event);
}
async function save() {
  saveDraft();
  await nextTick();
  headingActions.value?.querySelector<HTMLElement>("#sc-review-changes")?.focus();
}
</script>

<template>
  <div
    ref="root"
    class="spacecraft-study"
    :class="{ 'spacecraft-study--embedded': !standalone }"
    @keydown.esc="closeInspector"
  >
    <div class="sc-study-banner">
      <span><strong>DESIGN STUDY</strong> · Spacecraft configuration</span
      ><span>Sample mission · local simulation</span>
    </div>
    <header v-if="standalone" class="sc-app-bar">
      <div class="sc-app-identity">
        <span class="sc-brand" aria-hidden="true">C</span><strong>CADENCE</strong
        ><span class="sc-bar-divider" /><span class="sc-mission-mark" aria-hidden="true">K</span
        ><span>Kestrel</span><span class="sc-muted">/</span
        ><span class="sc-muted">Mission configuration</span>
      </div>
      <span class="sc-operator" aria-label="Sample mission engineer">ME</span>
    </header>
    <div class="sc-app-body">
      <aside v-if="standalone" class="sc-fleet">
        <header>
          <span class="hero-cube-transparent sc-icon" aria-hidden="true" />
          <h2>Spacecraft</h2>
          <span class="sc-count">{{ fleet.length }}</span>
        </header>
        <nav ref="fleetNavigation" aria-label="Mission spacecraft">
          <button
            v-for="craft in fleet"
            :key="craft.id"
            type="button"
            class="sc-fleet-item"
            :aria-label="`Open ${craft.id}`"
            :aria-pressed="selectedId === craft.id"
            @click="selectSpacecraft(craft.id)"
          >
            <span class="sc-fleet-item-top"
              ><span class="hero-cpu-chip sc-icon" aria-hidden="true" /><strong>{{
                craft.id
              }}</strong
              ><CadenceStatusSymbol
                :status="spacecraft[craft.id].active ? 'normal' : 'standby'" /></span
            ><span class="sc-fleet-role">{{ craft.role }}</span
            ><span class="sc-fleet-item-bottom"
              ><code>SCID {{ craft.scid }}</code
              ><span
                v-if="spacecraft[craft.id].active"
                :data-testid="`sc-fleet-revision-${craft.id}`"
                >r{{ spacecraft[craft.id].active?.catalog }}</span
              ><span v-else>New</span
              ><span
                v-if="
                  configurationChanges(spacecraft[craft.id].active, spacecraft[craft.id].draft)
                    .length
                "
                class="sc-draft-dot"
                aria-label="Has draft changes"
            /></span>
          </button>
        </nav>
        <div class="sc-fleet-summary">
          <span class="sc-eyebrow">MISSION FLEET</span>
          <p>{{ activeCount }} active configurations</p>
          <p>{{ fleet.length - activeCount }} awaiting setup</p>
          <div class="sc-fleet-legend">
            <CadenceStatusSymbol status="normal" /><span>Configuration active</span>
          </div>
          <div class="sc-fleet-legend">
            <CadenceStatusSymbol status="standby" /><span>Setup incomplete</span>
          </div>
        </div>
      </aside>
      <section class="sc-workspace" aria-label="Spacecraft configuration study">
        <div class="sc-page-heading">
          <CadencePageHeading id="sc-spacecraft-heading"
            ><template #eyebrow>SPACECRAFT / {{ identity?.role }}</template
            ><template #title>{{ selectedId }}</template
            ><template #metadata
              ><span class="sc-identity-metadata"
                ><span>SCID {{ identity?.scid }}</span
                ><span aria-hidden="true">·</span><span>{{ identity?.hardware }}</span></span
              ></template
            ><template #actions
              ><div ref="headingActions" class="sc-heading-actions">
                <SpacecraftSwitcher
                  v-if="!standalone"
                  :selected="selectedId"
                  :spacecraft="spacecraft"
                  @select="selectSpacecraft"
                />
                <span class="sc-header-state"
                  ><CadenceStatusSymbol :status="current.active ? 'normal' : 'standby'" />{{
                    current.active ? `Active r${current.active.catalog}` : "No active configuration"
                  }}</span
                ><CadenceButton
                  v-if="changes.length"
                  id="sc-review-changes"
                  size="sm"
                  @click="navigate('changes')"
                  >Review changes<span class="sc-count">{{ changes.length }}</span></CadenceButton
                ><CadenceButton
                  size="sm"
                  :disabled="!canOpenOps"
                  :title="
                    canOpenOps
                      ? 'Preview active command definitions'
                      : 'Activate a configuration with Commanding enabled to open Ops'
                  "
                  @click="navigate('ops')"
                  >Open in Ops<span class="hero-arrow-up-right sc-icon-sm" aria-hidden="true"
                /></CadenceButton></div></template
          ></CadencePageHeading>
        </div>
        <nav v-if="section !== 'ops'" class="sc-section-nav" aria-label="Spacecraft sections">
          <button
            v-for="item in sections"
            :key="item.id"
            type="button"
            :aria-label="item.label"
            :aria-current="section === item.id ? 'page' : undefined"
            @click="navigate(item.id)"
          >
            <span :class="[item.icon, 'sc-icon']" aria-hidden="true" />{{ item.label
            }}<span v-if="item.id === 'changes' && changes.length" class="sc-count">{{
              changes.length
            }}</span></button
          ><span class="sc-edit-state">{{
            unsaved
              ? "Unsaved edits"
              : changes.length
                ? "Draft saved"
                : current.active
                  ? "Saved & active"
                  : "New spacecraft"
          }}</span>
        </nav>
        <p v-if="feedback" class="sc-feedback" role="status">
          <span class="hero-check-circle sc-icon-sm" aria-hidden="true" />{{ feedback }}
        </p>
        <div class="sc-content" :class="{ 'sc-content--inspecting': inspector }">
          <div class="sc-section">
            <ConfigurationOverview
              v-if="section === 'overview'"
              :spacecraft="selectedId"
              :active="current.active"
              :draft="draft"
              :changes="changes.length"
              :issues="issues"
              :generation="current.history.length"
              @navigate="navigate"
              @inspect="openInspector"
              @repair="repair"
            />
            <CatalogApplications
              v-else-if="section === 'catalog'"
              :spacecraft="selectedId"
              :draft="draft"
              :active="current.active"
              :mission-navigation="!standalone"
              @inspect="openInspector"
            />
            <CommunicationsSetup
              v-else-if="section === 'communications'"
              :draft="draft"
              @edit="edit"
              @preset="applyPreset"
              @inspect="openInspector"
            />
            <ConfigurationChanges
              v-else-if="section === 'changes'"
              :spacecraft="selectedId"
              :state="current"
              :changes="changes"
              :issues="issues"
              :unsaved="unsaved"
              :can-review="canReview"
              :can-activate="canActivate"
              @repair="repair"
              @submit="submitReview"
              @approve="simulateApproval"
              @activate="activate"
            />
            <CommandingHandoff
              v-else-if="current.active"
              :key="selectedId"
              :spacecraft="selectedId"
              :active="current.active"
              :draft="draft"
              @back="navigate('overview')"
            />
          </div>
          <ConfigurationInspector
            v-if="inspector"
            :key="`${selectedId}-${inspector}`"
            :kind="inspector"
            :spacecraft="selectedId"
            :draft="draft"
            :active="current.active"
            @close="closeInspector"
            @edit="edit"
            @choose-revision="chooseRevision"
            @choose-catalog="openInspector('catalog', $event)"
          />
        </div>
        <footer v-if="unsaved" class="sc-draft-bar" aria-label="Unsaved configuration">
          <span class="sc-draft-indicator" aria-hidden="true" />
          <div>
            <strong>Unsaved changes</strong
            ><span
              >{{ selectedId }} ·
              {{
                current.active ? `active r${current.active.catalog} stays in use` : "not yet active"
              }}</span
            >
          </div>
          <CadenceButton size="sm" variant="quiet" @click="discardUnsaved"
            >Discard unsaved</CadenceButton
          ><CadenceButton size="sm" variant="primary" @click="save">Save draft</CadenceButton>
        </footer>
      </section>
    </div>
  </div>
</template>
