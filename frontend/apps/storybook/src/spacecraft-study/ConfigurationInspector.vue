<script setup lang="ts">
import { ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import {
  revisions,
  revisionLabel,
  type Configuration,
  type Inspector,
  type RevisionId,
} from "./fixtures";

defineProps<{
  kind: Inspector;
  spacecraft: string;
  draft: Configuration;
  active: Configuration | null;
}>();
defineEmits<{
  close: [];
  edit: [patch: Partial<Configuration>];
  chooseRevision: [revision: RevisionId];
  chooseCatalog: [event: MouseEvent];
}>();
const selectedRevision = ref<RevisionId>("3.4");
const title = {
  catalog: "Choose catalog revision",
  telemetry: "Telemetry Decom",
  commanding: "Commanding",
  route: "S-band delivery path",
};
const search = ref("");
const revisionOptions = [revisions["3.4"], revisions["3.3"]];
</script>

<template>
  <aside class="sc-inspector" aria-labelledby="sc-inspector-title">
    <header class="sc-inspector-heading">
      <div>
        <p class="sc-eyebrow">
          {{ spacecraft }} / {{ kind === "catalog" ? "ONBOARD COMPUTER" : "CONFIGURATION" }}
        </p>
        <h2 id="sc-inspector-title" tabindex="-1">{{ title[kind] }}</h2>
      </div>
      <CadenceButton size="sm" variant="quiet" aria-label="Close inspector" @click="$emit('close')"
        ><span class="hero-x-mark sc-icon" aria-hidden="true"
      /></CadenceButton>
    </header>
    <div class="sc-inspector-body">
      <template v-if="kind === 'catalog'">
        <div class="sc-current-binding">
          <span class="sc-eyebrow">ACTIVE ON THIS SPACECRAFT</span
          ><strong>{{ revisionLabel(active?.catalog ?? null) }}</strong>
        </div>
        <label class="fieldset"
          ><span class="sc-eyebrow">IMPORTED CATALOGS</span
          ><input
            v-model="search"
            class="input w-full"
            type="search"
            aria-label="Find imported catalogs"
            placeholder="Find a catalog or revision…"
        /></label>
        <fieldset class="sc-radio-group">
          <legend class="sr-only">Catalog revision</legend>
          <label
            v-for="revision in revisionOptions.filter((item) =>
              `Kestrel FSW ${item.id}`.toLowerCase().includes(search.toLowerCase()),
            )"
            :key="revision.id"
            class="sc-revision-option"
            :class="{ 'is-selected': selectedRevision === revision.id }"
          >
            <input
              v-model="selectedRevision"
              type="radio"
              name="catalog-revision"
              :value="revision.id"
              :aria-label="`Kestrel FSW revision ${revision.id}`"
            />
            <span
              ><strong
                >Kestrel FSW <code>r{{ revision.id }}</code></strong
              ><span>{{ revision.software }}</span
              ><span class="sc-option-meta"
                >Imported {{ revision.date
                }}<span v-if="revision.id === active?.catalog"> · Active here</span></span
              ></span
            >
          </label>
          <p
            v-if="
              !revisionOptions.some((item) =>
                `Kestrel FSW ${item.id}`.toLowerCase().includes(search.toLowerCase()),
              )
            "
            class="sc-muted"
          >
            No imported catalogs match. Clear the search to see available revisions.
          </p>
        </fieldset>
        <section class="sc-revision-detail" aria-label="Selected revision details">
          <div class="sc-block-heading sc-block-heading--plain">
            <h3>Revision {{ selectedRevision }}</h3>
            <span class="sc-count">Immutable</span>
          </div>
          <div class="sc-mini-metrics">
            <span
              ><strong>{{ revisions[selectedRevision].packets }}</strong
              >packets</span
            ><span
              ><strong>{{ revisions[selectedRevision].parameters }}</strong
              >parameters</span
            ><span
              ><strong>{{ revisions[selectedRevision].commands }}</strong
              >commands</span
            >
          </div>
          <p class="sc-eyebrow">
            {{ selectedRevision === "3.4" ? "ADDED SINCE 3.3" : "IN THIS REVISION" }}
          </p>
          <ul class="sc-definition-list">
            <li v-for="addition in revisions[selectedRevision].additions" :key="addition">
              <span class="hero-plus-small sc-icon-sm" aria-hidden="true" />{{ addition }}
            </li>
          </ul>
          <CadenceLink
            :href="`/iframe.html?id=design-studies-spacecraft-configuration--catalog-reference&viewMode=story#revision-${selectedRevision}`"
            target="_blank"
            rel="noopener"
            >Inspect catalog contents<span class="sr-only"> (opens in new tab)</span
            ><template #icon><span class="hero-arrow-top-right-on-square" /></template
          ></CadenceLink>
        </section>
        <div class="sc-inline-context">
          <span class="hero-arrow-turn-down-right sc-icon" aria-hidden="true" />
          <p>
            Enabled applications on <strong>{{ spacecraft }}</strong> will use this revision after
            activation. Other spacecraft keep their bindings.
          </p>
        </div>
      </template>
      <template v-else-if="kind === 'telemetry' || kind === 'commanding'">
        <p class="sc-muted">
          {{
            kind === "telemetry"
              ? "Decode spacecraft packets using the definitions bound to its onboard computer."
              : "Prepare commands using this spacecraft’s exact active definitions."
          }}
        </p>
        <div class="sc-current-binding">
          <span class="sc-eyebrow">CATALOG IN DRAFT</span
          ><strong>{{ revisionLabel(draft.catalog) }}</strong
          ><span v-if="draft.catalog" class="sc-muted">{{
            kind === "telemetry"
              ? `${revisions[draft.catalog].packets} packets · ${revisions[draft.catalog].parameters} parameters`
              : `${revisions[draft.catalog].commands} command definitions`
          }}</span>
        </div>
        <div v-if="!draft.catalog" class="sc-stack">
          <p class="sc-muted">Choose a catalog before enabling this application.</p>
          <CadenceButton size="sm" variant="primary" @click="$emit('chooseCatalog', $event)"
            >Choose catalog</CadenceButton
          >
        </div>
        <CadenceCheckbox
          v-else
          :id="`sc-enable-${kind}`"
          :model-value="kind === 'telemetry' ? draft.telemetryEnabled : draft.commandingEnabled"
          @update:model-value="
            $emit(
              'edit',
              kind === 'telemetry' ? { telemetryEnabled: $event } : { commandingEnabled: $event },
            )
          "
          >Enable {{ title[kind] }}</CadenceCheckbox
        >
        <template v-if="kind === 'telemetry' && draft.telemetryEnabled">
          <div>
            <h3>Packet input</h3>
            <p class="sc-muted">Connect the stream carrying OBC telemetry.</p>
          </div>
          <fieldset class="sc-radio-group">
            <legend class="sr-only">Telemetry packet input</legend>
            <label
              class="sc-revision-option"
              :class="{ 'is-selected': draft.telemetryInput === 'obc-vc0' }"
              ><input
                type="radio"
                name="telemetry-input"
                :checked="draft.telemetryInput === 'obc-vc0'"
                aria-label="OBC downlink VC 0"
                @change="$emit('edit', { telemetryInput: 'obc-vc0' })"
              /><span
                ><strong>OBC downlink</strong><span>VC 0 · APIDs 0–127</span
                ><span class="sc-compatible">Compatible with Kestrel FSW</span></span
              ></label
            >
            <label class="sc-revision-option sc-revision-option--unavailable"
              ><input
                type="radio"
                name="telemetry-input"
                disabled
                aria-label="Payload downlink VC 1 — requires a payload catalog"
              /><span
                ><strong>Payload downlink</strong><span>VC 1 · APIDs 256–511</span
                ><span>Requires a payload catalog</span></span
              ></label
            >
          </fieldset>
          <div v-if="draft.telemetryInput" class="sc-input-summary">
            <span class="hero-check-circle sc-icon" aria-hidden="true" />
            <p>
              <strong
                >{{ draft.catalog ? revisions[draft.catalog].packets : 0 }} packet definitions
                matched</strong
              ><span>OBC downlink → Telemetry Decom</span>
            </p>
          </div>
          <CadenceButton
            v-if="draft.telemetryInput"
            size="xs"
            variant="quiet"
            @click="$emit('edit', { telemetryInput: null })"
            >Disconnect packet input</CadenceButton
          >
        </template>
        <template v-if="kind === 'commanding' && draft.commandingEnabled">
          <dl class="sc-facts sc-facts--inset">
            <div>
              <dt>Target</dt>
              <dd>{{ spacecraft }}</dd>
            </div>
            <div>
              <dt>Endpoint</dt>
              <dd>Onboard computer</dd>
            </div>
            <div>
              <dt>Uplink</dt>
              <dd>{{ draft.uplink ?? "Configure in Communications" }}</dd>
            </div>
          </dl>
          <p class="sc-section-note">
            Saving this setting enables command preparation after activation. Command review,
            release and execution happen in Ops.
          </p>
        </template>
      </template>
      <template v-else>
        <p class="sc-muted">
          Mission transport shared by this spacecraft’s downlink and uplink routes.
        </p>
        <div class="sc-route-diagram">
          <span>Ground station</span><span aria-hidden="true">↕</span
          ><strong>S-band · primary</strong><span aria-hidden="true">↕</span
          ><span>{{ spacecraft }} · onboard computer</span>
        </div>
        <dl class="sc-facts sc-facts--inset">
          <div>
            <dt>Downlink destination</dt>
            <dd>OBC · VC 0</dd>
          </div>
          <div>
            <dt>Uplink destination</dt>
            <dd>Onboard computer</dd>
          </div>
          <div>
            <dt>Framing in draft</dt>
            <dd>{{ draft.downlink ?? "—" }} / {{ draft.uplink ?? "—" }}</dd>
          </div>
        </dl>
        <p class="sc-section-note">
          This view shows configured delivery paths. A configured route does not imply an available
          contact.
        </p>
      </template>
    </div>
    <footer class="sc-inspector-footer">
      <template v-if="kind === 'catalog'"
        ><span class="sc-muted">{{
          draft.catalog === selectedRevision ? "Already selected in draft" : `Bind to ${spacecraft}`
        }}</span
        ><CadenceButton
          size="sm"
          variant="primary"
          :disabled="draft.catalog === selectedRevision"
          @click="$emit('chooseRevision', selectedRevision)"
          >Use r{{ selectedRevision }} in draft</CadenceButton
        ></template
      >
      <template v-else
        ><span class="sc-muted">{{
          kind === "route" ? "Route details" : "Edits stay in this spacecraft’s draft"
        }}</span
        ><CadenceButton size="sm" @click="$emit('close')">Done</CadenceButton></template
      >
    </footer>
  </aside>
</template>
