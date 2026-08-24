defmodule CadenceWeb.Catalog.Components do
  @moduledoc false
  use CadenceWeb, :html

  @doc "Colored badge for an import run status."
  attr :status, :atom, required: true

  def import_run_status_badge(assigns) do
    ~H"""
    <.status_badge status={badge_status(@status)} label={status_label(@status)} />
    """
  end

  defp badge_status(:running), do: :info
  defp badge_status(:completed), do: :ready
  defp badge_status(:failed), do: :blocked
  defp badge_status(_), do: :info

  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
  defp status_label(other), do: other |> to_string() |> String.capitalize()

  @doc "Grouped diagnostic list for an import run."
  attr :diagnostics, :list, required: true

  def diagnostic_list(assigns) do
    assigns = assign(assigns, :groups, group_diagnostics(assigns.diagnostics))

    ~H"""
    <div :if={@diagnostics != []} class="space-y-3">
      <.card :for={{severity, items} <- @groups} title={"#{severity_heading(severity)} (#{length(items)})"}>
        <ul class="space-y-2">
          <li :for={diagnostic <- items} class="text-sm">
            <span class="font-mono text-xs text-base-content/60">{diagnostic.code}</span>
            <span class="ml-2">{diagnostic.message}</span>
            <p
              :if={diagnostic_detail(diagnostic) != nil}
              class="text-xs text-base-content/70 mt-1"
            >
              {diagnostic_detail(diagnostic)}
            </p>
            <p :if={diagnostic.path != []} class="text-xs text-base-content/60 font-mono mt-1">
              {Enum.join(diagnostic.path, " / ")}
            </p>
          </li>
        </ul>
      </.card>
    </div>
    """
  end

  defp group_diagnostics(diagnostics) do
    [:error, :warning, :info]
    |> Enum.map(fn severity ->
      {severity, Enum.filter(diagnostics, &(&1.severity == severity))}
    end)
    |> Enum.reject(fn {_, items} -> items == [] end)
  end

  defp severity_heading(:error), do: "Errors"
  defp severity_heading(:warning), do: "Warnings"
  defp severity_heading(:info), do: "Info"

  defp diagnostic_detail(diagnostic) do
    metadata = Map.get(diagnostic, :metadata, %{}) || %{}

    [
      metadata_value(metadata, "consumption_summary", "Built-in telemetry"),
      metadata_value(metadata, "consumption_status", "Status"),
      metadata_value(metadata, "packet_name", "Packet"),
      metadata_value(metadata, "entry_name", "Entry"),
      metadata_value(metadata, "point_name", "Point"),
      metadata_value(metadata, "type_name", "Type"),
      metadata_value(metadata, "base_type", "Base type"),
      metadata_value(metadata, "point_id", "Point ID"),
      metadata_value(metadata, "type_id", "Type ID")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " | ")
    end
  end

  defp metadata_value(metadata, key, label) do
    case Map.get(metadata, key) do
      value when is_binary(value) and value != "" -> "#{label}: #{value}"
      _ -> nil
    end
  end

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

  @doc "Summary count card for a snapshot (telemetry or command)."
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :counts, :list, required: true, doc: "Keyword list of {label, integer}."
  attr :navigate, :string, default: nil

  def snapshot_summary_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-center gap-2 mb-3">
        <span class={[@icon, "h-4 w-4"]}></span>
        <p class="hud-label">{@title}</p>
      </div>
      <div class="divide-y divide-base-300">
        <.detail_row :for={{label, count} <- @counts} label={label} mono>
          {count}
        </.detail_row>
      </div>
      <div :if={@navigate} class="flex justify-end mt-3">
        <.button variant={:ghost} size={:xs} navigate={@navigate}>
          View details <span class="hero-arrow-right h-3 w-3 ml-1"></span>
        </.button>
      </div>
    </.card>
    """
  end
end
