defmodule CadenceWeb.Catalog.Components do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.ExtensionCatalog

  @doc "JSON-safe upload configuration and server-mapped validation errors for LiveVue."
  def upload_dto(upload) do
    %{
      ref: upload.ref,
      name: to_string(upload.name),
      accept: upload_accept_dto(upload.accept),
      max_entries: upload.max_entries,
      max_file_size: upload.max_file_size,
      auto_upload: upload.auto_upload?,
      entries: Enum.map(upload.entries, &upload_entry_dto(upload, &1)),
      errors: Enum.map(upload.errors, fn {ref, error} -> upload_error_dto(ref, error) end)
    }
  end

  @doc "JSON-safe presentation of the server-authoritative importer detection result."
  def detected_importer_dto(entries) do
    case detect_importer_from_entries(entries) do
      {:ok, %{descriptor: descriptor}} ->
        %{status: "detected", display_name: descriptor.display_name}

      {:error, :no_matching_importer} ->
        %{status: "unsupported", display_name: nil}

      _other ->
        %{status: "empty", display_name: nil}
    end
  end

  @doc "Returns true when a detected importer result is `{:ok, _}`."
  def importer_detected?({:ok, _registration}), do: true
  def importer_detected?(_), do: false

  @doc "Detects an importer from a list of LiveView upload entries."
  def detect_importer_from_entries([%{client_name: name, client_type: type} | _]) do
    ExtensionCatalog.detect_catalog_importer(name, type)
  end

  def detect_importer_from_entries(_), do: nil

  @doc "Human-readable message for a LiveView upload error atom."
  def upload_error_message(:too_large), do: "File exceeds the 50 MB limit."
  def upload_error_message(:not_accepted), do: "File type is not accepted."
  def upload_error_message(:too_many_files), do: "Only one file at a time."
  def upload_error_message(other), do: "Upload failed: #{inspect(other)}"

  defp upload_accept_dto(:any), do: false
  defp upload_accept_dto(accept) when is_binary(accept), do: accept
  defp upload_accept_dto(_accept), do: false

  defp upload_entry_dto(upload, entry) do
    %{
      ref: entry.ref,
      client_name: entry.client_name,
      client_size: entry.client_size,
      client_type: entry.client_type,
      progress: entry.progress,
      done: entry.done?,
      valid: entry.valid?,
      preflighted: entry.preflighted?,
      errors: Enum.map(upload_errors(upload, entry), &upload_error_code/1)
    }
  end

  defp upload_error_dto(ref, error) do
    %{
      ref: ref,
      error: upload_error_code(error),
      code: upload_error_code(error),
      message: upload_error_message(error)
    }
  end

  defp upload_error_code(error) when is_atom(error), do: Atom.to_string(error)
  defp upload_error_code(error), do: inspect(error)
end
