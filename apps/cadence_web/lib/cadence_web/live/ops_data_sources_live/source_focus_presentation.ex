defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusPresentation do
  @moduledoc """
  Evidence and remediation presentation models for focused dashboard sources.
  """

  alias Cadence.DataSources.DataSource
  alias CadenceWeb.OpsDataSourcesLive.SourceContract

  @spec evidence(map()) :: map() | nil
  def evidence(%{selected_evidence_kind: nil, selected_source_evidence_mode: nil}), do: nil

  def evidence(focus) when is_map(focus) do
    kind = focus.selected_evidence_kind || "source"
    mode = focus.selected_source_evidence_mode || "health"
    state = focus.selected_source_evidence_state || evidence_state(focus)
    reason = focus.source_empty_reason || "source_evidence"

    %{
      kind: kind,
      mode: mode,
      state: state || "unknown",
      reason: reason,
      title: evidence_title(mode, state),
      detail: evidence_detail(focus, mode, state, reason)
    }
  end

  @spec remediation(map(), [DataSource.t()]) :: map() | nil
  def remediation(focus, data_sources)
  def remediation(%{source_empty_reason: nil}, _data_sources), do: nil

  def remediation(%{source_empty_reason: "missing_source_binding"} = focus, _data_sources) do
    %{
      kind: "missing_source_binding",
      title: "Publish blocker: no source binding resolves",
      detail:
        "Register a compatible source if needed, then bind #{focus_text(focus.logical_source)} / #{focus_text(focus.realm)} for this mission context.",
      action: :register_source,
      target: "source_registration",
      target_id: nil,
      capability_rows: [],
      candidate_rows: []
    }
  end

  def remediation(%{source_empty_reason: "missing_data_source"} = focus, _data_sources) do
    source_remediation(
      focus,
      "missing_data_source",
      "Publish blocker: binding points at a missing source",
      "Register the missing data source or change the highlighted binding to an active source."
    )
  end

  def remediation(%{source_empty_reason: "disabled_data_source"} = focus, _data_sources) do
    source_review_remediation(
      focus,
      "disabled_data_source",
      "Publish blocker: source is disabled",
      "Review the highlighted source and enable it or move the binding to an active source."
    )
  end

  def remediation(
        %{source_empty_reason: "unsupported_source_capability"} = focus,
        data_sources
      ) do
    source_remediation(
      focus,
      "unsupported_source_capability",
      "Publish blocker: source capability mismatch",
      "Use the highlighted binding's Change action to select a source whose capabilities match the planned widget request.",
      capability_rows: capability_mismatch_rows(focus),
      candidate_rows: capability_candidate_rows(focus, data_sources)
    )
  end

  def remediation(%{source_empty_reason: "source_unavailable"} = focus, _data_sources) do
    source_review_remediation(
      focus,
      "source_unavailable",
      "Publish blocker: source unavailable",
      "Probe or repair the highlighted source, then refresh publish readiness."
    )
  end

  def remediation(%{source_empty_reason: "source_degraded"} = focus, _data_sources) do
    source_review_remediation(
      focus,
      "source_degraded",
      "Publish blocker: source health degraded",
      "Review the highlighted source health and restore it or change the binding to a healthier source."
    )
  end

  def remediation(
        %{source_empty_reason: "invalid_data_source_configuration"} = focus,
        _data_sources
      ) do
    source_review_remediation(
      focus,
      "invalid_data_source_configuration",
      "Publish blocker: source configuration is invalid",
      "Review the highlighted source adapter, credentials, dataset, and endpoint configuration."
    )
  end

  def remediation(
        %{source_empty_reason: "source_binding_interval_ambiguous"} = focus,
        _data_sources
      ) do
    source_remediation(
      focus,
      "source_binding_interval_ambiguous",
      "Publish blocker: binding interval is ambiguous",
      "Adjust binding activation intervals so this publish context resolves to exactly one active binding."
    )
  end

  def remediation(_focus, _data_sources), do: nil

  defp evidence_state(%{source_empty_reason: "stale_data"}), do: "stale"
  defp evidence_state(%{source_empty_reason: "retention_gap"}), do: "retention_gap"
  defp evidence_state(%{source_empty_reason: "watermark_unknown"}), do: "unknown"
  defp evidence_state(%{source_empty_reason: "unknown_watermark"}), do: "unknown"
  defp evidence_state(_focus), do: nil

  defp evidence_title("execution", _state), do: "Source execution evidence"
  defp evidence_title(_mode, "stale"), do: "Source freshness evidence is stale"
  defp evidence_title(_mode, "retention_gap"), do: "Source freshness has a retention gap"
  defp evidence_title(_mode, "unknown"), do: "Source freshness evidence is unknown"
  defp evidence_title(_mode, _state), do: "Source evidence"

  defp evidence_detail(focus, mode, state, reason) do
    [
      "kind=#{focus.selected_evidence_kind || "source"}",
      "mode=#{mode || "health"}",
      "state=#{state || "unknown"}",
      "reason=#{reason}",
      evidence_identity(focus)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp evidence_identity(focus) do
    cond do
      is_binary(focus.source_binding_id) and is_binary(focus.data_source_id) ->
        "source=#{focus.source_binding_id}->#{focus.data_source_id}"

      is_binary(focus.source_binding_id) ->
        "source_binding_id=#{focus.source_binding_id}"

      is_binary(focus.data_source_id) ->
        "data_source_id=#{focus.data_source_id}"

      true ->
        nil
    end
  end

  defp source_remediation(focus, kind, title, detail, opts \\ []) do
    %{
      kind: kind,
      title: title,
      detail: detail,
      action: remediation_action(focus),
      target: remediation_target(focus),
      target_id: remediation_target_id(focus),
      capability_rows: Keyword.get(opts, :capability_rows, []),
      candidate_rows: Keyword.get(opts, :candidate_rows, [])
    }
  end

  defp source_review_remediation(focus, kind, title, detail) do
    %{
      kind: kind,
      title: title,
      detail: detail,
      action: review_action(focus),
      target: review_target(focus),
      target_id: review_target_id(focus),
      capability_rows: [],
      candidate_rows: []
    }
  end

  defp capability_mismatch_rows(focus) do
    [
      capability_row("sampling", "sampling", focus.requested_sampling, focus.supported_sampling),
      capability_row("products", "products", focus.requested_products, focus.supported_products),
      capability_row(
        "source_products",
        "source products",
        focus.requested_source_products,
        focus.supported_products
      ),
      capability_row(
        "product_families",
        "product families",
        focus.requested_product_families,
        focus.supported_product_families
      ),
      capability_row(
        "value_kinds",
        "value kinds",
        focus.requested_value_kinds,
        focus.supported_value_kinds
      ),
      capability_row("shapes", "shapes", focus.requested_shapes, focus.supported_shapes),
      capability_row(
        "time_axes",
        "time axes",
        focus.requested_time_axes,
        focus.supported_time_axes
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp capability_row(_key, _label, nil, nil), do: nil

  defp capability_row(key, label, requested, supported) do
    %{
      key: key,
      label: label,
      requested: focus_text(requested),
      supported: focus_text(supported)
    }
  end

  defp capability_candidate_rows(focus, sources) do
    sources
    |> Enum.filter(&candidate_source?(&1, focus))
    |> Enum.map(&capability_candidate_row(&1, focus))
    |> Enum.sort_by(fn candidate -> {not candidate.compatible?, candidate.data_source_id} end)
  end

  defp candidate_source?(%DataSource{} = source, focus) do
    DataSource.active?(source) and
      SourceContract.logical_source_text(source) == focus.logical_source
  end

  defp capability_candidate_row(%DataSource{} = source, focus) do
    missing = SourceContract.missing_requirements(source, focus)
    compatible? = missing == []

    %{
      data_source_id: source.data_source_id,
      compatible?: compatible?,
      status_text: if(compatible?, do: "compatible", else: "blocked"),
      missing_text: missing_requirements_text(missing),
      reason_text: candidate_reason_text(missing)
    }
  end

  defp candidate_reason_text([]), do: "matches requested contract"
  defp candidate_reason_text(missing), do: "missing #{missing_requirements_text(missing)}"

  defp missing_requirements_text([]), do: "none"

  defp missing_requirements_text(missing) do
    Enum.map_join(missing, ";", fn {field, values} -> "#{field}=#{Enum.join(values, ",")}" end)
  end

  defp remediation_action(%{matched_source_binding_id: binding_id}) when is_binary(binding_id),
    do: :review_binding

  defp remediation_action(_focus), do: :register_source

  defp remediation_target(%{matched_source_binding_id: binding_id}) when is_binary(binding_id),
    do: "binding"

  defp remediation_target(_focus), do: "source_registration"

  defp remediation_target_id(%{matched_source_binding_id: binding_id}) when is_binary(binding_id),
    do: binding_id

  defp remediation_target_id(_focus), do: nil

  defp review_action(%{matched_data_source_id: data_source_id}) when is_binary(data_source_id),
    do: :review_source

  defp review_action(focus), do: remediation_action(focus)

  defp review_target(%{matched_data_source_id: data_source_id}) when is_binary(data_source_id),
    do: "source"

  defp review_target(focus), do: remediation_target(focus)

  defp review_target_id(%{matched_data_source_id: data_source_id}) when is_binary(data_source_id),
    do: data_source_id

  defp review_target_id(focus), do: remediation_target_id(focus)

  defp focus_text(nil), do: "unknown"
  defp focus_text(value), do: value
end
