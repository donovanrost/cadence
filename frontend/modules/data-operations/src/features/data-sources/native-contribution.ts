import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import NativeDataSources from "./NativeDataSources.vue";
import { admitSourcePage, sourceActions } from "./native-contract";
export const sourceContributions = (
  [
    ["sources", "reader"],
    ["source", "reader"],
    ["source-registration", "registration"],
    ["source-settings", "settings"],
  ] as const
).map(
  ([name, mode]) =>
    ({
      id: `data-operations.${name}`,
      slot: "ops.page",
      version: 1,
      title: "Data Sources",
      // Oxlint does not resolve this SFC constructor; vue-tsc checks its public props.
      // oxlint-disable-next-line typescript/no-unsafe-assignment
      component: NativeDataSources,
      query: true,
      actions: sourceActions,
      read(value, context) {
        const page = admitSourcePage(
          value,
          { organization_id: context.organizationId, mission_id: context.missionId },
          mode,
        );
        if (!page || (name === "source" && !page.model.selected))
          throw Error("Source evidence is unavailable");
        return { page };
      },
    }) satisfies OpsPageContribution<Component>,
);
