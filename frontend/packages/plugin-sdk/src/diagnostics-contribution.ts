/** Build-time UI composition, independent of federation and installation policy. */
export const ADMINISTRATION_DIAGNOSTICS_SLOT = "administration.diagnostics" as const;

export type DiagnosticsSnapshot = {
  id: string;
  version: number;
  status: "ready" | "unavailable";
  data?: unknown;
};

export type DiagnosticsPanelInteractions = {
  /** Changes filters on the current diagnostics page, never its resource scope. */
  updateQuery: (query: Record<string, string>) => void;
};

export type DiagnosticsContribution<TComponent = unknown> = {
  readonly id: string;
  readonly slot: typeof ADMINISTRATION_DIAGNOSTICS_SLOT;
  readonly version: 1;
  readonly title: string;
  readonly order: number;
  readonly component: TComponent;
  /** Feature-owned DTO validation must throw before malformed data is rendered. */
  readonly validate: (value: unknown) => void;
};
