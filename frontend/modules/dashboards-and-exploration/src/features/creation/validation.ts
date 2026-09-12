import type { CreationState } from "./contracts";
export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid creation data");
  return value as Record<string, unknown>;
}
export function text(value: unknown, max = 512): string {
  if (typeof value !== "string" || value.length > max) throw Error("Invalid creation text");
  return value;
}
export function identity(value: unknown): string {
  const id = text(value, 256);
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  if (!id || /[\u0000-\u001f]/.test(id)) throw Error("Invalid creation identity");
  return id;
}
export function integer(value: unknown, min = 0): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < min)
    throw Error("Invalid creation number");
  return value;
}
export function readCreation(value: unknown, mission: string): CreationState {
  const state = record(value),
    model = record(state.model);
  if (
    model.version !== 1 ||
    !mission ||
    model.mission_id !== mission ||
    !["new", "clone", "import"].includes(model.mode as string) ||
    !["editing", "submitted"].includes(state.phase as string)
  )
    throw Error("Invalid creation context");
  const source = model.source === null ? null : record(model.source);
  if ((model.mode === "clone") !== (source !== null)) throw Error("Invalid clone source");
  return {
    sequence: integer(state.sequence),
    phase: state.phase as CreationState["phase"],
    model: {
      version: 1,
      mission_id: mission,
      mode: model.mode as CreationState["model"]["mode"],
      source: source && {
        id: identity(source.id),
        name: text(source.name),
        description: source.description === null ? null : text(source.description, 4096),
        version: integer(source.version, 1),
        widget_count: integer(source.widget_count),
      },
    },
  };
}
