import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import AlarmConditionsPanel from "./AlarmConditionsPanel.vue";
import { admitAlarmDocument } from "./contracts";
export const alarmConditionsContribution = {
  id: "limits.alarm-conditions",
  slot: "ops.page",
  version: 1,
  title: "Alarm conditions",
  component: AlarmConditionsPanel,
  navigation: true,
  query: true,
  read(value, context) {
    const model = admitAlarmDocument(value, context);
    if (!model) throw Error("Unavailable alarm conditions.");
    return { model, context };
  },
} as const satisfies OpsPageContribution<Component>;
