defmodule CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.{DataLinkAttrs, EvidenceAttrs}

  attr :warning, :map, required: true
  attr :placement_id, :string, default: nil

  def engine_warning_badge(assigns) do
    ~H"""
    <.popover
      id={"engine-warning-#{@placement_id || "dashboard"}-#{@warning.code_text}"}
      label={@warning.label}
      width={:md}
      data-engine-warning-detail={@warning.code_text}
      data-limit-selected-clock={warning_detail_value(@warning, :selected_limit_clock)}
      data-limit-missing-samples={warning_detail_value(@warning, :missing_sample_ids)}
      data-limit-mode={warning_detail_value(@warning, :requested_semantics_mode)}
    >
      <:trigger>
        <span
          class={["badge badge-xs cursor-pointer", warning_badge_class(@warning)]}
          data-engine-warning={@warning.code_text}
          title={@warning.message}
        >{@warning.label}</span>
      </:trigger>
      <div class="p-2 text-xs">
        <div class="font-semibold text-base-content">{@warning.label}</div>
        <p class="mt-1 text-base-content/70">{@warning.message}</p>
        <button
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.warning(@warning, @placement_id)}
          class="mt-2 btn btn-xs btn-outline w-full justify-start"
          data-warning-evidence-open
        >
          <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" />
          Inspect evidence
        </button>
        <dl
          :if={@warning.detail_rows != []}
          class="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1"
        >
          <%= for row <- @warning.detail_rows do %>
            <dt class="text-base-content/60">{row.label}</dt>
            <dd class="font-mono text-base-content break-all" data-warning-detail={row.label}>
              {row.value}
            </dd>
          <% end %>
        </dl>
        <div :if={@warning.evidence != []} class="mt-2 space-y-1" data-warning-evidence>
          <div class="font-semibold text-base-content/80">Evidence</div>
          <div
            :for={evidence <- @warning.evidence}
            class="grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1"
            data-warning-evidence-kind={evidence.kind_text}
            data-warning-evidence-id={evidence.id || ""}
          >
            <span class="text-base-content/60">{evidence.kind_text}</span>
            <span class="font-mono text-base-content break-all">{evidence.id}</span>
            <span class="text-base-content/60">Source</span>
            <span class="font-mono text-base-content break-all">{evidence.source_text}</span>
            <span class="text-base-content/60">Observed</span>
            <span class="font-mono text-base-content break-all">{evidence.observed_at_text}</span>
          </div>
        </div>
        <div :if={@warning.links != []} class="mt-2 space-y-1" data-warning-links>
          <div class="font-semibold text-base-content/80">Data links</div>
          <button
            :for={link <- @warning.links}
            type="button"
            phx-click="open_data_link"
            {DataLinkAttrs.open(link,
              placement_id: @placement_id,
              context_fallback: warning_data_link_context_fallback(@warning)
            )}
            class="grid w-full grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left hover:border-primary/60 hover:bg-base-200"
            data-warning-link-target={link.target_text}
            data-warning-link-id={link.target_id || ""}
            data-warning-link-ref={link.link_id || ""}
          >
            <span class="text-base-content/60">{link.target_text}</span>
            <span class="font-mono text-base-content break-all">{link.target_id}</span>
            <span class="text-base-content/60">Source</span>
            <span class="font-mono text-base-content break-all">{link.source_text}</span>
          </button>
        </div>
      </div>
    </.popover>
    """
  end

  def warning_codes(warnings) when is_list(warnings) do
    Enum.map_join(warnings, ",", & &1.code_text)
  end

  def warning_codes(_warnings), do: ""

  defp warning_badge_class(%{severity: :error}), do: "badge-error"
  defp warning_badge_class(%{severity: :warning}), do: "badge-warning"
  defp warning_badge_class(_warning), do: "badge-info"

  defp warning_data_link_context_fallback(%{details: details}) when is_map(details), do: details
  defp warning_data_link_context_fallback(_warning), do: %{}

  defp warning_detail_value(%{details: details}, key) when is_map(details) do
    details
    |> Map.get(key, Map.get(details, Atom.to_string(key)))
    |> warning_detail_text()
  end

  defp warning_detail_value(_warning, _key), do: nil

  defp warning_detail_text(nil), do: nil
  defp warning_detail_text(value) when is_atom(value), do: Atom.to_string(value)
  defp warning_detail_text(value) when is_binary(value), do: value

  defp warning_detail_text(values) when is_list(values),
    do: Enum.map_join(values, ",", &warning_detail_text/1)

  defp warning_detail_text(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      "#{warning_detail_text(key)}=#{warning_detail_text(nested_value)}"
    end)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp warning_detail_text(value), do: to_string(value)
end
