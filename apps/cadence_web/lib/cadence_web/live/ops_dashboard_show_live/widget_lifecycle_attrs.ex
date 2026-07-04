defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecycleAttrs do
  @moduledoc false

  alias Cadence.Dashboards.FrameLifecycle

  @severities %{
    ready: :ok,
    no_data: :info,
    stale: :warning,
    partial: :warning,
    retention_gap: :error,
    error: :error,
    unsupported: :error
  }

  @spec attrs(map() | nil, [map()]) :: map()
  def attrs(data, warnings \\ []) do
    lifecycle = lifecycle(data)
    state = FrameLifecycle.state(lifecycle)

    %{
      "data-widget-lifecycle-state" => Atom.to_string(state),
      "data-widget-lifecycle-severity" => atom_text(severity(lifecycle, state)),
      "data-widget-lifecycle-reasons" => code_list(Map.get(lifecycle, :reason_codes, [])),
      "data-widget-lifecycle-warning-codes" => code_list(Map.get(lifecycle, :warning_codes, [])),
      "data-widget-placement-warning-codes" => code_list(Enum.map(warnings, &warning_code/1))
    }
    |> Map.merge(source_status_attrs(data))
  end

  defp lifecycle(%{lifecycle: lifecycle}) when is_map(lifecycle), do: lifecycle

  defp lifecycle(%{lifecycle_state: state})
       when state in [:ready, :no_data, :stale, :partial, :retention_gap],
       do: lifecycle_from_state(state)

  defp lifecycle(%{lifecycle_state: state}) when state in [:error, :unsupported],
    do: lifecycle_from_state(state)

  defp lifecycle(nil), do: lifecycle_from_state(:no_data)
  defp lifecycle(_data), do: FrameLifecycle.classify(%{})

  defp lifecycle_from_state(state) do
    %{
      state: state,
      severity: Map.fetch!(@severities, state),
      reason_codes: reason_codes(state),
      warning_codes: []
    }
  end

  defp reason_codes(:ready), do: []
  defp reason_codes(state), do: [state]

  defp severity(%{severity: severity}, _state) when is_atom(severity), do: severity
  defp severity(_lifecycle, state), do: Map.fetch!(@severities, state)

  defp warning_code(%{code: code}), do: code
  defp warning_code(%{code_text: code_text}), do: code_text
  defp warning_code(_warning), do: nil

  defp source_status_attrs(%{source_status: source_status}) when is_map(source_status) do
    %{
      "data-widget-source-state" => source_status |> Map.get(:state) |> attr_text(),
      "data-widget-source-severity" => source_status |> Map.get(:severity) |> attr_text(),
      "data-widget-source-data-state" => source_status |> Map.get(:data_state) |> attr_text(),
      "data-widget-source-stale" => boolean_text(Map.get(source_status, :stale?)),
      "data-widget-source-warning-codes" => code_list(Map.get(source_status, :warning_codes, [])),
      "data-widget-source-freshness-states" =>
        code_list(Map.get(source_status, :freshness_states, [])),
      "data-widget-source-confidences" => code_list(Map.get(source_status, :confidences, [])),
      "data-widget-source-logical-sources" =>
        code_list(Map.get(source_status, :logical_sources, [])),
      "data-widget-source-request-ids" =>
        code_list(Map.get(source_status, :source_request_ids, [])),
      "data-widget-source-data-source-ids" =>
        code_list(Map.get(source_status, :data_source_ids, [])),
      "data-widget-source-binding-ids" =>
        code_list(Map.get(source_status, :source_binding_ids, [])),
      "data-widget-source-realms" => code_list(Map.get(source_status, :realms, [])),
      "data-widget-source-time-modes" => code_list(Map.get(source_status, :time_modes, [])),
      "data-widget-source-time-axes" => code_list(Map.get(source_status, :time_axes, [])),
      "data-widget-source-replay-run-ids" =>
        code_list(Map.get(source_status, :replay_run_ids, [])),
      "data-widget-source-scope-kinds" => code_list(Map.get(source_status, :scope_kinds, [])),
      "data-widget-source-scope-ids" => code_list(Map.get(source_status, :scope_ids, [])),
      "data-widget-source-contact-ids" => code_list(Map.get(source_status, :contact_ids, [])),
      "data-widget-source-source-endpoint-ids" =>
        code_list(Map.get(source_status, :source_endpoint_ids, [])),
      "data-widget-source-empty-reason" =>
        source_status |> Map.get(:empty_reason) |> empty_reason_text()
    }
  end

  defp source_status_attrs(_data) do
    %{
      "data-widget-source-state" => "",
      "data-widget-source-severity" => "",
      "data-widget-source-data-state" => "",
      "data-widget-source-stale" => "",
      "data-widget-source-warning-codes" => "",
      "data-widget-source-freshness-states" => "",
      "data-widget-source-confidences" => "",
      "data-widget-source-logical-sources" => "",
      "data-widget-source-request-ids" => "",
      "data-widget-source-data-source-ids" => "",
      "data-widget-source-binding-ids" => "",
      "data-widget-source-realms" => "",
      "data-widget-source-time-modes" => "",
      "data-widget-source-time-axes" => "",
      "data-widget-source-replay-run-ids" => "",
      "data-widget-source-scope-kinds" => "",
      "data-widget-source-scope-ids" => "",
      "data-widget-source-contact-ids" => "",
      "data-widget-source-source-endpoint-ids" => "",
      "data-widget-source-empty-reason" => ""
    }
  end

  defp code_list(codes) do
    codes
    |> List.wrap()
    |> Enum.map(&atom_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp atom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_text(value) when is_binary(value), do: value
  defp atom_text(_value), do: nil

  defp attr_text(value), do: atom_text(value) || ""

  defp empty_reason_text(nil), do: ""
  defp empty_reason_text(value), do: attr_text(value)

  defp boolean_text(true), do: "true"
  defp boolean_text(false), do: "false"
  defp boolean_text(_value), do: ""
end
