<script setup lang="ts">
import { computed, nextTick, ref, shallowRef, watch } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { serverHref } from "@cadence/plugin-sdk/routes";
import CadenceResourceNavigation from "@cadence/ui/CadenceResourceNavigation.vue";
import SpacecraftSwitcher from "./SpacecraftSwitcher.vue";
import ConfigurationOverview from "./ConfigurationOverview.vue";
import CatalogApplications from "./CatalogApplications.vue";
import CommunicationsSetup from "./CommunicationsSetup.vue";
import ConfigurationChanges from "./ConfigurationChanges.vue";
import ConfigurationInspector from "./ConfigurationInspector.vue";
import {
  readConfiguration,
  readDocument,
  type ConfigurationDocument,
  type ConfigurationIdentity,
  type ConfigurationPort,
  type Inspector,
} from "./contracts";
import { equalDocuments, type ConfigurationDrafts } from "./drafts";
import { configurationChanges, revisionLabel, sections, setupIssues } from "./presentation";
import "./spacecraft-configuration.css";
const props = defineProps<{
  data: unknown;
  identity: ConfigurationIdentity;
  port: ConfigurationPort;
  drafts: ConfigurationDrafts;
}>();
const snapshot = computed(() => readConfiguration(props.data, props.identity));
const session = shallowRef(props.drafts.receive(snapshot.value));
watch(snapshot, (value) => {
  session.value = props.drafts.receive(value);
});
const draft = computed(() => session.value.draft);
const unsaved = computed(
  () => !equalDocuments(draft.value, session.value.baseline) || snapshot.value.external_changes,
);
const changes = computed(() => configurationChanges(snapshot.value, draft.value));
useManagementHeader("/missions/:mission_id/spacecraft/:spacecraft_id", () => {
  const current = snapshot.value;
  const editIdentity = {
    id: "spacecraft-edit-identity",
    label: "Edit identity",
    icon: "hero-identification",
    href: serverHref(current.links.identity),
  } as const;
  const openOps = (link: string) =>
    ({
      id: "spacecraft-open-ops",
      label: "Open in Ops",
      icon: "hero-arrow-up-right",
      href: serverHref(link),
    }) as const;
  return {
    title: current.name,
    facts: [
      `SCID ${current.scid ?? "—"}`,
      current.active
        ? current.active.version
          ? `Active r${current.active.version}`
          : "Active legacy configuration"
        : "No active configuration",
    ],
    actions: current.links.ops ? [editIdentity, openOps(current.links.ops)] : [editIdentity],
  };
});
const issues = computed(() => setupIssues(draft.value));
const inspector = ref<Inspector | null>(null);
const root = ref<HTMLElement | null>(null);
let trigger: HTMLElement | null = null;
async function inspect(kind: Inspector, event: MouseEvent) {
  trigger = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
  inspector.value = kind;
  await focusInspector();
}
async function focusInspector() {
  await nextTick();
  root.value?.querySelector<HTMLElement>("#spacecraft-inspector-focus")?.focus();
}
async function closeInspector() {
  inspector.value = null;
  await nextTick();
  if (trigger?.isConnected) trigger.focus();
}
function edit(patch: Partial<ConfigurationDocument>) {
  if (!session.value.busy) {
    session.value.draft = { ...draft.value, ...patch };
    session.value.feedback = null;
  }
}
function useLatest() {
  session.value.draft = snapshot.value.document;
  session.value.baseline = snapshot.value.document;
  session.value.token = snapshot.value.token;
  session.value.conflict = false;
  session.value.feedback = null;
}
function keepEdits() {
  session.value.baseline = snapshot.value.document;
  session.value.token = snapshot.value.token;
  session.value.conflict = false;
  session.value.feedback =
    "Your edits are retained against the latest saved revision. Review the comparison before saving.";
}
const latestChanges = computed(() =>
  configurationChanges(
    { ...snapshot.value, active: { version: 0, generation: 0, document: snapshot.value.document } },
    draft.value,
  ),
);
async function save() {
  const current = session.value;
  if (current.busy || current.conflict) return;
  let document: ConfigurationDocument;
  try {
    document = readDocument(current.draft);
  } catch {
    current.feedback = "Check framing values and packet selections before saving.";
    return;
  }
  current.busy = true;
  const result = await props.port.save(current.token, document);
  current.feedback =
    result.status === "ok" ? "Draft saved. Active configuration remains in use." : result.message;
  current.busy = false;
}
async function review() {
  const current = session.value;
  if (current.busy || current.conflict || unsaved.value) return;
  current.feedback = null;
  current.busy = true;
  const result =
    snapshot.value.approval.requirement === "direct"
      ? await props.port.activate(current.token, snapshot.value.approval.token)
      : await props.port.review(current.token, snapshot.value.approval.token);
  current.feedback = result.message;
  current.busy = false;
}
async function decide(reason: string, decision: "approved" | "rejected") {
  const current = session.value;
  const request = snapshot.value.review;
  if (current.busy || current.conflict || unsaved.value || !request) return;
  current.feedback = null;
  current.busy = true;
  const result = await props.port.decide(current.token, request.id, reason, decision);
  current.feedback = result.message;
  current.busy = false;
}
</script>
<template>
  <div id="spacecraft-configuration-workspace" ref="root" class="scw" @keydown.esc="closeInspector">
    <div class="flex justify-end">
      <SpacecraftSwitcher :snapshot="snapshot" :drafts="drafts" />
    </div>
    <CadenceResourceNavigation label="Spacecraft sections"
      ><a
        v-for="item in sections"
        :key="item.id"
        :href="`${snapshot.base_href}?section=${item.id}`"
        :aria-current="snapshot.section === item.id ? 'page' : undefined"
        ><span :class="[item.icon, 'scw-icon']" aria-hidden="true" />{{ item.label
        }}<span v-if="item.id === 'changes' && changes.length" class="scw-count">{{
          changes.length
        }}</span></a
      ><template #status>{{
        unsaved
          ? "Unsaved edits"
          : changes.length
            ? "Draft saved"
            : snapshot.active
              ? "Saved & active"
              : "Awaiting setup"
      }}</template></CadenceResourceNavigation
    >
    <p v-if="snapshot.section !== 'changes' && session.feedback" class="scw-feedback" role="status">
      {{ session.feedback }}
    </p>
    <section
      v-if="session.conflict"
      class="scw-conflict"
      aria-labelledby="spacecraft-conflict-title"
    >
      <h2 id="spacecraft-conflict-title">The saved configuration changed</h2>
      <p>
        Your edits are preserved. Compare them with the latest saved revision before continuing.
      </p>
      <dl>
        <div v-for="change in latestChanges" :key="change.label">
          <dt>{{ change.label }}</dt>
          <dd>Saved: {{ change.before }} → Your draft: {{ change.after }}</dd>
        </div>
      </dl>
      <div class="scw-actions">
        <CadenceButton size="sm" @click="useLatest">Use latest saved</CadenceButton
        ><CadenceButton size="sm" @click="keepEdits">Keep my edits</CadenceButton>
      </div>
    </section>
    <div class="scw-content" :class="{ 'scw-content--inspecting': inspector }">
      <div class="scw-section">
        <ConfigurationOverview
          v-if="snapshot.section === 'overview'"
          :snapshot="snapshot"
          :draft="draft"
          :changes="changes.length"
          :issues="issues"
          @inspect="inspect"
        />
        <CatalogApplications
          v-else-if="snapshot.section === 'catalog'"
          :snapshot="snapshot"
          :draft="draft"
          @inspect="inspect"
        />
        <CommunicationsSetup
          v-else-if="snapshot.section === 'communications'"
          :snapshot="snapshot"
          :draft="draft"
          :busy="session.busy"
          @edit="edit"
        />
        <ConfigurationChanges
          v-else
          :snapshot="snapshot"
          :draft="draft"
          :unsaved="unsaved"
          :issues="issues"
          :busy="session.busy"
          :conflict="session.conflict"
          :feedback="session.feedback"
          @review="review"
          @decide="decide"
        />
      </div>
      <ConfigurationInspector
        v-if="inspector"
        :kind="inspector"
        :snapshot="snapshot"
        :draft="draft"
        :port="port"
        :busy="session.busy"
        @close="closeInspector"
        @edit="edit"
        @choose-catalog="
          inspector = 'catalog';
          focusInspector();
        "
      />
    </div>
    <footer v-if="unsaved" class="scw-draft-bar" aria-label="Unsaved configuration">
      <span class="scw-draft-dot" aria-hidden="true" />
      <div>
        <strong>Unsaved changes</strong
        ><span
          >{{ snapshot.name }} ·
          {{
            snapshot.active
              ? revisionLabel(snapshot, snapshot.active.document.catalog_revision_id)
              : "not yet active"
          }}</span
        >
      </div>
      <CadenceButton size="sm" variant="quiet" :disabled="session.busy" @click="useLatest"
        >Discard unsaved</CadenceButton
      ><CadenceButton
        id="spacecraft-save-draft"
        size="sm"
        variant="primary"
        :disabled="session.busy || session.conflict"
        @click="save"
        >{{ session.busy ? "Working…" : "Save draft" }}</CadenceButton
      >
    </footer>
  </div>
</template>
