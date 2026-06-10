defmodule CadenceWeb.Catalog.Components do
  @moduledoc false
  use CadenceWeb, :html

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
            <p :if={diagnostic.path != []} class="text-xs text-base-content/50 font-mono mt-1">
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

  alias Cadence.Catalog.Registry

  @doc "Upload card with importer auto-detection."
  attr :uploads, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true

  def upload_card(assigns) do
    assigns =
      assign(
        assigns,
        :detected_importer,
        detect_importer_from_entries(assigns.uploads.artifact.entries)
      )

    ~H"""
    <.card title="Create catalog database revision">
      <div class="space-y-4 mt-2">
        <p class="text-sm text-base-content/60">
          Save the upload as an immutable revision in the mission catalog library. Runtime
          usage is chosen separately.
        </p>

        <.form
          id="catalog-upload-form"
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:name]} type="text" label="Catalog database name" />
            <.input field={@form[:revision_label]} type="text" label="Revision label" />
          </div>
          <.input field={@form[:revision_notes]} type="textarea" label="Revision notes" />

          <label class="block">
            <.live_file_input upload={@uploads.artifact} class="file-input file-input-bordered w-full" />
          </label>

          <ul :if={@uploads.artifact.entries != []} class="space-y-1">
            <li
              :for={entry <- @uploads.artifact.entries}
              class="flex items-center justify-between text-sm"
            >
              <span class="font-mono">{entry.client_name} ({entry.client_type || "unknown"})</span>
              <.button
                variant={:ghost}
                size={:xs}
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
              >
                Remove
              </.button>
            </li>
          </ul>

          <.upload_error_alert :for={err <- upload_errors(@uploads.artifact)} error={err} />

          <.detected_preview detected={@detected_importer} />

          <div class="flex items-center gap-3">
            <.button type="submit" size={:md} disabled={!importer_detected?(@detected_importer)}>
              Upload &amp; import
            </.button>
          </div>
        </.form>
      </div>
    </.card>
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
    <.card>
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
        <.button variant={:ghost} size={:xs} navigate={@navigate}>
          View details <span class="hero-arrow-right h-3 w-3 ml-1"></span>
        </.button>
      </div>
    </.card>
    """
  end
end
