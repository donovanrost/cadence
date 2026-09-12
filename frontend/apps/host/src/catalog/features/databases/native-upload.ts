import type { CatalogUploadSession } from "./upload-contract";

/** The native form remains Phoenix-owned; Vue only delegates user intent. */
export function nativeUpload(session: CatalogUploadSession, values: Record<string, string>) {
  const form = document.getElementById("catalog-native-upload-form");
  if (
    !(form instanceof HTMLFormElement) ||
    form.dataset.catalogPath !== session.path ||
    form.dataset.catalogToken !== session.token
  )
    throw new Error("The upload session changed. Reopen the Catalog page and try again.");

  const fields: Record<string, string> = { ...values, path: session.path, token: session.token };
  for (const key of ["path", "token", "name", "revision_label", "revision_notes"]) {
    const input = form.elements.namedItem(`catalog_upload[${key}]`);
    if (!(input instanceof HTMLInputElement)) throw new Error("Upload controls are unavailable.");
    input.value = fields[key] ?? "";
  }
  const uploads = form.querySelectorAll<HTMLInputElement>(
    'input[type="file"][name="catalog_artifact"][data-phx-upload-ref]',
  );
  const file = uploads[0];
  if (
    uploads.length !== 1 ||
    !file ||
    !file.dataset.phxUploadRef ||
    file.id !== file.dataset.phxUploadRef
  )
    throw new Error("Upload controls are unavailable.");
  return { form, file };
}
