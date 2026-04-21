defmodule CadenceWeb.Catalog.Components do
  @moduledoc false
  use CadenceWeb, :html

  @doc "Colored badge for a catalog family atom (`:telemetry | :command | :combined`)."
  attr :family, :atom, required: true

  def catalog_family_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      family_badge_class(@family)
    ]}>
      {family_label(@family)}
    </span>
    """
  end

  defp family_badge_class(:telemetry), do: "badge-info"
  defp family_badge_class(:command), do: "badge-warning"
  defp family_badge_class(:combined), do: "badge-primary"
  defp family_badge_class(_), do: "badge-ghost"

  defp family_label(:telemetry), do: "Telemetry"
  defp family_label(:command), do: "Command"
  defp family_label(:combined), do: "Combined"

  defp family_label(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.capitalize()

  @doc "Colored badge for an import run status."
  attr :status, :atom, required: true

  def import_run_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      status_badge_class(@status)
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_badge_class(:running), do: "badge-info"
  defp status_badge_class(:completed), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

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
      <div :for={{severity, items} <- @groups} class="card bg-base-200">
        <div class="card-body p-4">
          <p class="hud-label mb-2">{severity_heading(severity)} ({length(items)})</p>
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
              <p :if={diagnostic.path != []} class="text-xs text-base-content/50 font-mono mt-1">
                {Enum.join(diagnostic.path, " / ")}
              </p>
            </li>
          </ul>
        </div>
      </div>
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

  alias Cadence.Catalog.Registry

  @doc "Upload card with importer auto-detection."
  attr :uploads, :map, required: true

  def upload_card(assigns) do
    assigns =
      assign(
        assigns,
        :detected_importer,
        detect_importer_from_entries(assigns.uploads.artifact.entries)
      )

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-6 space-y-4">
        <p class="hud-label">Upload command &amp; telemetry database</p>

        <.form
          id="catalog-upload-form"
          for={%{}}
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <label class="block">
            <.live_file_input upload={@uploads.artifact} class="file-input file-input-bordered w-full" />
          </label>

          <ul :if={@uploads.artifact.entries != []} class="space-y-1">
            <li
              :for={entry <- @uploads.artifact.entries}
              class="flex items-center justify-between text-sm"
            >
              <span class="font-mono">{entry.client_name} ({entry.client_type || "unknown"})</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="btn btn-ghost btn-xs"
              >
                Remove
              </button>
            </li>
          </ul>

          <.upload_error_alert :for={err <- upload_errors(@uploads.artifact)} error={err} />

          <.detected_preview detected={@detected_importer} />

          <div class="flex items-center gap-3">
            <button
              type="submit"
              class="btn btn-primary"
              disabled={!importer_detected?(@detected_importer)}
            >
              Upload &amp; import
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @doc "Error alert for a LiveView upload entry error."
  attr :error, :atom, required: true

  def upload_error_alert(assigns) do
    ~H"""
    <div class="alert alert-error text-sm">
      {upload_error_message(@error)}
    </div>
    """
  end

  @doc "Preview of a detected importer or a no-match error message."
  attr :detected, :any, required: true

  def detected_preview(assigns) do
    ~H"""
    <%= case @detected do %>
      <% {:ok, %{descriptor: descriptor}} -> %>
        <div class="flex items-center gap-2 text-sm text-base-content/80">
          <span class="hero-check-circle h-4 w-4 text-success"></span>
          Detected importer:
          <span class="font-medium">{descriptor.display_name}</span>
          <.catalog_family_badge family={descriptor.catalog_family} />
        </div>
      <% {:error, :no_matching_importer} -> %>
        <div class="alert alert-error text-sm">
          <p>
            No importer supports this file. Accepted formats: YAML (<code>.yaml</code>, <code>.yml</code>).
          </p>
        </div>
      <% _ -> %>
        <div class="text-xs text-base-content/50">
          Select a file to see the detected importer.
        </div>
    <% end %>
    """
  end

  @doc "Returns true when a detected importer result is `{:ok, _}`."
  def importer_detected?({:ok, _registration}), do: true
  def importer_detected?(_), do: false

  @doc "Detects an importer from a list of LiveView upload entries."
  def detect_importer_from_entries([%{client_name: name, client_type: type} | _]) do
    Registry.detect_importer(name, type)
  end

  def detect_importer_from_entries(_), do: nil

  @doc "Human-readable message for a LiveView upload error atom."
  def upload_error_message(:too_large), do: "File exceeds the 50 MB limit."
  def upload_error_message(:not_accepted), do: "File type is not accepted."
  def upload_error_message(:too_many_files), do: "Only one file at a time."
  def upload_error_message(other), do: "Upload failed: #{inspect(other)}"

  @doc "Summary count card for a snapshot (telemetry or command)."
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :counts, :list, required: true, doc: "Keyword list of {label, integer}."
  attr :navigate, :string, default: nil

  def snapshot_summary_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class={[@icon, "h-4 w-4"]}></span>
          <p class="hud-label">{@title}</p>
        </div>
        <dl class="grid grid-cols-2 gap-2 text-sm">
          <div :for={{label, count} <- @counts} class="contents">
            <dt class="text-base-content/60">{label}</dt>
            <dd class="font-mono text-base-content text-right">{count}</dd>
          </div>
        </dl>
        <div :if={@navigate} class="card-actions justify-end mt-3">
          <.link navigate={@navigate} class="btn btn-ghost btn-xs">
            View details <span class="hero-arrow-right h-3 w-3 ml-1"></span>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
