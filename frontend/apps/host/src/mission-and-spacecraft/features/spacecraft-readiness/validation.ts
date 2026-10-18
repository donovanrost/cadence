import {
  SPACECRAFT_READINESS_SLOT,
  type ReadinessContext,
  type ReadinessContribution,
} from "@cadence/plugin-sdk/readiness";
import {
  assertShape,
  choice,
  href,
  list,
  nullable,
  record,
  shape,
  text,
} from "../../shared/validation.ts";
const status = shape({ tone: choice("ready", "attention", "blocked", "info"), label: text });
const detail = shape({ label: text, value: text });
const action = shape({ label: text, href });
const context = shape({ organizationId: text, missionId: text, spacecraftId: text });
export function assertSpacecraftReadiness(value: unknown): void {
  assertShape(
    shape({
      page: shape({
        id: choice("spacecraft-readiness-page"),
        title: text,
        title_suffix: text,
        subtitle: text,
        breadcrumbs: list(shape({ label: text, href: nullable(href) })),
        status,
      }),
      context,
      contributions: list(() => true),
      panels: list(
        shape({
          id: text,
          title: text,
          status,
          description: text,
          details: list(detail),
          action,
          application_list: nullable(
            shape({ id: text, empty_state: shape({ id: text, description: text }) }),
          ),
        }),
      ),
      applications: list(shape({ id: text, application_key: text, display_name: text, status })),
    }),
    value,
  );
}
const boundedText = (value: unknown) => text(value) && (value as string).length <= 4096;
const contribution = shape({
  id: boundedText,
  title: boundedText,
  slot: choice(SPACECRAFT_READINESS_SLOT),
  version: choice(1),
  context,
  availability: choice("available", "unavailable"),
  status: shape({ tone: choice("ready", "attention", "blocked", "info"), label: boundedText }),
  details: list(shape({ label: boundedText, value: boundedText })),
  action: nullable(shape({ label: boundedText, href })),
});
export function admitContributions(
  values: unknown[],
  scope: ReadinessContext,
): (ReadinessContribution | null)[] {
  const counts = new Map<unknown, number>();
  for (const value of values)
    if (record(value)) counts.set(value.id, (counts.get(value.id) ?? 0) + 1);
  return values.map((value) => {
    if (!contribution(value)) return null;
    const item = value as ReadinessContribution;
    if (
      counts.get(item.id) !== 1 ||
      !/^[a-z][a-z0-9_.-]{0,254}$/.test(item.id) ||
      item.details.length > 64 ||
      item.context.organizationId !== scope.organizationId ||
      item.context.missionId !== scope.missionId ||
      item.context.spacecraftId !== scope.spacecraftId ||
      (item.availability === "unavailable" && item.status.tone !== "blocked")
    )
      return null;
    return item;
  });
}
