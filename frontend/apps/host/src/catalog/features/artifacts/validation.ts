import {
  assertShape,
  attrs,
  element,
  href,
  label,
  list,
  nullable,
  shape,
  text,
  tone,
} from "../../shared/validation.ts";
export function assertArtifact(value: unknown): void {
  assertShape(
    shape({
      presentation: shape({
        root: element,
        child_wrapper: element,
        header: shape({
          attrs,
          body: element,
          content: element,
          title: label,
          breadcrumbs: shape({
            attrs,
            items: list(
              shape({
                key: text,
                separator: nullable(label),
                link: nullable(label),
                current: nullable(label),
              }),
            ),
          }),
        }),
        artifact_show: shape({
          artifact: shape({
            format_key: text,
            media_type: text,
            content_sha256: text,
            uploaded_at: text,
            download_href: href,
          }),
          runs: list(
            shape({
              id: text,
              actions_id: text,
              status: tone,
              status_label: text,
              started_at: text,
              completed_at: text,
              href,
            }),
          ),
        }),
      }),
    }),
    value,
  );
}
