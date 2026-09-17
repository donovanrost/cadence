<script setup lang="ts">
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import { fleet, revisions, type SpacecraftId } from "./fixtures";
import { spacecraftPath } from "./navigation";
import type { SpacecraftState } from "./state";
defineProps<{
  spacecraft: Readonly<Record<SpacecraftId, SpacecraftState>>;
  selected: SpacecraftId;
}>();
</script>

<template>
  <div class="sc-catalog-destination">
    <CadencePageHeading
      ><template #eyebrow>MISSION CATALOG</template><template #title>Catalog</template
      ><template #description>Imported definitions and the spacecraft that use them.</template
      ><template #actions
        ><CadenceLink :href="spacecraftPath(selected)"
          >Return to {{ selected
          }}<template #icon><span class="hero-arrow-right" /></template></CadenceLink></template
    ></CadencePageHeading>
    <div class="sc-stack sc-stack--large">
      <section class="sc-surface">
        <header class="sc-block-heading">
          <h2>Kestrel FSW</h2>
          <span class="sc-count">2 imported revisions</span>
        </header>
        <div class="sc-catalog-revisions">
          <div v-for="revision in [revisions['3.4'], revisions['3.3']]" :key="revision.id">
            <span class="sc-revision">r{{ revision.id }}</span>
            <div>
              <strong>{{ revision.software }}</strong>
              <p class="sc-muted">
                {{ revision.packets }} packets · {{ revision.commands }} commands · imported
                {{ revision.date }}
              </p>
            </div>
          </div>
        </div>
      </section>
      <section class="sc-surface" aria-labelledby="sc-catalog-usage-title">
        <header class="sc-block-heading">
          <h2 id="sc-catalog-usage-title">Spacecraft usage</h2>
          <span class="sc-muted">Onboard computer bindings</span>
        </header>
        <div class="sc-diff-scroll">
          <CadenceTableFrame>
            <caption class="sr-only">
              Active and draft catalog revisions in this sample mission
            </caption>
            <thead>
              <tr>
                <th scope="col">Spacecraft</th>
                <th scope="col">Active revision</th>
                <th scope="col">Draft revision</th>
                <th scope="col">Applications in draft</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="craft in fleet" :key="craft.id">
                <th scope="row">
                  <CadenceLink :href="spacecraftPath(craft.id)">{{ craft.id }}</CadenceLink>
                </th>
                <td>
                  {{
                    spacecraft[craft.id].active
                      ? `r${spacecraft[craft.id].active?.catalog}`
                      : "Not activated"
                  }}
                </td>
                <td>
                  {{
                    spacecraft[craft.id].draft.catalog
                      ? `r${spacecraft[craft.id].draft.catalog}`
                      : "Not bound"
                  }}
                </td>
                <td>
                  {{
                    [
                      spacecraft[craft.id].draft.telemetryEnabled ? "Telemetry Decom" : null,
                      spacecraft[craft.id].draft.commandingEnabled ? "Commanding" : null,
                    ]
                      .filter(Boolean)
                      .join(" · ") || "None enabled"
                  }}
                </td>
              </tr>
            </tbody>
          </CadenceTableFrame>
        </div>
        <p class="sc-section-note">
          Open a spacecraft to configure its binding. Draft changes remain with that spacecraft when
          you navigate away.
        </p>
      </section>
    </div>
  </div>
</template>

<style scoped>
.sc-catalog-destination {
  font: 13px/1.5 var(--font-sans);
}
.sc-catalog-destination h2 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}
.sc-catalog-revisions {
  display: flex;
  flex-wrap: wrap;
  gap: 20px 40px;
  padding: 24px;
}
.sc-catalog-revisions > div {
  display: flex;
  align-items: center;
  gap: 16px;
}
.sc-catalog-revisions p {
  margin: 4px 0 0;
}
</style>
