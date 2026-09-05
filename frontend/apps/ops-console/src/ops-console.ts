import type { Component } from "vue";

export const OPS_QUERY_ID = "cadence.ops.console" as const;
export const OPS_QUERY_VERSION = 1 as const;

export type OpsConsolePresentation = {
  component: string;
  props: Record<string, unknown>;
};

export type OpsConsoleResponse = {
  queryVersion: typeof OPS_QUERY_VERSION;
  presentation: OpsConsolePresentation;
};

export function unwrapOpsConsoleResponse(
  value: unknown,
  components: Record<string, Component>,
): OpsConsolePresentation {
  if (!isRecord(value) || value.queryVersion !== OPS_QUERY_VERSION || !isRecord(value.presentation)) {
    throw new Error("The Ops Console response is invalid.");
  }

  const {component, props} = value.presentation;
  if (typeof component !== "string" || !components[component] || !isRecord(props)) {
    throw new Error("The Ops Console presentation component is invalid.");
  }

  return {component, props};
}

function isRecord(value: unknown): value is Record<string, any> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
