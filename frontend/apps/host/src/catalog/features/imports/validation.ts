import {
  assertShape,
  breadcrumbs,
  count,
  list,
  nullable,
  shape,
  text,
  tone,
} from "../../shared/validation.ts";
export function assertImportRun(value: unknown): void {
  assertShape(
    shape({
      navigation: breadcrumbs,
      status: shape({ label: text, tone }),
      run_details: shape({
        importer: shape({ id: text, label: text }),
        started_at: text,
        completed_at: nullable(text),
      }),
      mission_model: nullable(
        shape({
          id: text,
          revision_id: nullable(text),
          declaration_count: nullable(count),
          plan_count: count,
        }),
      ),
      diagnostic_groups: list(
        shape({
          title: text,
          items: list(
            shape({ code: text, message: text, detail: nullable(text), path: nullable(text) }),
          ),
        }),
      ),
      failure_reason: nullable(text),
    }),
    value,
  );
}
