defmodule Cadence.Dashboards.Sources.Limits.RequestPolicy do
  @moduledoc """
  Validates limits source requests and builds adapter policy warnings.

  This module owns product selection, required request context, supported
  semantics, and the warning policy shared across limits resolution paths.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    PlannedSourceRequest,
    ResolveWarning,
    SourceWatermark
  }

  alias Cadence.Dashboards.Sources.Limits.RecomputedAnalysis
  alias Cadence.Limits.{DefinitionInterval, Event}

  @supported_products [:latest_state, :event_history, :definition_intervals, :analysis_buckets]

  @spec validate(PlannedSourceRequest.t()) ::
          {:ok, atom(), binary(), binary()} | {:warning, ResolveWarning.t()}
  def validate(%PlannedSourceRequest{} = request) do
    with :ok <- ensure_limits_source(request),
         {:ok, product} <- requested_product(request),
         :ok <- ensure_supported_semantics(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      {:ok, product, mission_id, organization_id}
    end
  end

  @spec recomputed_capability(atom()) :: atom()
  def recomputed_capability(:compare), do: :limit_comparison_analysis
  def recomputed_capability(:current), do: :current_limit_analysis
  def recomputed_capability(:recomputed), do: :recomputed_limit_analysis
  def recomputed_capability(_semantics_mode), do: :limit_event_history

  @spec watermark_warnings(PlannedSourceRequest.t(), SourceWatermark.t()) ::
          [ResolveWarning.t()]
  def watermark_warnings(
        %PlannedSourceRequest{},
        %SourceWatermark{confidence: confidence}
      )
      when confidence in [:authoritative, :best_effort],
      do: []

  def watermark_warnings(%PlannedSourceRequest{} = request, %SourceWatermark{}) do
    unknown_watermark_warnings(request)
  end

  @spec unknown_watermark_warnings(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def unknown_watermark_warnings(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Limits source watermark confidence is unknown",
        %{
          unresolved_capability: :source_watermark
        }
      )
    ]
  end

  @spec missing_state_warnings(PlannedSourceRequest.t(), binary(), Event.t() | nil) ::
          [ResolveWarning.t()]
  def missing_state_warnings(%PlannedSourceRequest{} = request, observable_id, nil) do
    [
      warning(
        request,
        :unknown_limit_definition,
        :info,
        "No latest observed limit state is available for observable",
        %{observable_id: observable_id}
      )
    ]
  end

  def missing_state_warnings(%PlannedSourceRequest{}, _observable_id, %Event{}), do: []

  @spec missing_interval_warnings(
          PlannedSourceRequest.t(),
          binary(),
          [DefinitionInterval.t()]
        ) :: [ResolveWarning.t()]
  def missing_interval_warnings(%PlannedSourceRequest{} = request, observable_id, []) do
    [
      warning(
        request,
        :unknown_limit_definition,
        :info,
        "No effective limit definition interval is available for observable",
        %{observable_id: observable_id}
      )
    ]
  end

  def missing_interval_warnings(%PlannedSourceRequest{}, _observable_id, _intervals), do: []

  @spec incomplete_interval_warnings(
          PlannedSourceRequest.t(),
          binary(),
          [DefinitionInterval.t()]
        ) :: [ResolveWarning.t()]
  def incomplete_interval_warnings(
        %PlannedSourceRequest{} = request,
        observable_id,
        intervals
      ) do
    incomplete_intervals = Enum.reject(intervals, & &1.complete?)

    if incomplete_intervals == [] do
      []
    else
      [
        warning(
          request,
          :incomplete_limit_definition_intervals,
          :warning,
          "Some limit-definition intervals are missing hydrated definition payloads",
          %{
            observable_id: observable_id,
            missing_limit_definitions:
              Enum.map(incomplete_intervals, fn interval ->
                %{
                  limit_definition_id: interval.limit_definition_id,
                  limit_definition_version: interval.limit_definition_version,
                  limit_definition_lifecycle_event_id:
                    interval.limit_definition_lifecycle_event_id
                }
              end)
          }
        )
      ]
    end
  end

  @spec degraded?([ResolveWarning.t()]) :: boolean()
  def degraded?(warnings) do
    Enum.any?(warnings, &(&1.severity != :info))
  end

  @spec supported_capability(PlannedSourceRequest.t()) :: atom()
  def supported_capability(%PlannedSourceRequest{} = request) do
    case requested_product(request) do
      {:ok, :event_history} -> :limit_event_history
      {:ok, :analysis_buckets} -> :limit_analysis_buckets
      {:ok, :definition_intervals} -> :limit_definition_intervals
      _other -> :latest_limit_state
    end
  end

  defp ensure_limits_source(%PlannedSourceRequest{logical_source: :limits}), do: :ok

  defp ensure_limits_source(%PlannedSourceRequest{} = request) do
    {:warning,
     warning(
       request,
       :unsupported_logical_source,
       :error,
       "Limits adapter cannot resolve source",
       %{
         logical_source: request.logical_source
       }
     )}
  end

  defp ensure_observables([observable | _rest]) when is_binary(observable), do: :ok

  defp ensure_observables(_observables) do
    {:warning,
     %ResolveWarning{
       code: :missing_observables,
       severity: :error,
       scope: :dashboard,
       message: "Limits source request does not include observables"
     }}
  end

  defp ensure_supported_semantics(%PlannedSourceRequest{} = request) do
    case RecomputedAnalysis.semantics_mode(request) do
      semantics_mode when semantics_mode in [:observed, :current, :recomputed, :compare] ->
        :ok

      semantics_mode ->
        {:warning,
         warning(
           request,
           :unsupported_limit_semantics_mode,
           :warning,
           "Limits source supports observed, current, recomputed, and compare limit semantics",
           unsupported_limit_semantics_details(request, semantics_mode)
         )}
    end
  end

  defp unsupported_limit_semantics_details(%PlannedSourceRequest{} = request, semantics_mode) do
    %{
      requested_semantics_mode: semantics_mode,
      requested_analysis_basis: RecomputedAnalysis.analysis_basis(semantics_mode),
      selected_limit_clock: RecomputedAnalysis.limit_clock_policy(request),
      supported_semantics_modes: [:observed, :current, :recomputed, :compare],
      supported_analysis_basis: [
        :observed_fact,
        :current_definition_analysis,
        :recomputed_analysis,
        :limit_comparison_analysis
      ],
      required_inputs: required_inputs_for_semantics(semantics_mode),
      future_capability: future_capability_for_semantics(semantics_mode)
    }
  end

  defp required_inputs_for_semantics(:current) do
    [
      :current_limit_definition_projection,
      :telemetry_sample_read_path,
      :dashboard_limit_recompute_engine
    ]
  end

  defp required_inputs_for_semantics(:recomputed) do
    [
      :historical_telemetry_sample_read_path,
      :target_limit_definition_intervals,
      :selected_limit_clock_policy,
      :dashboard_limit_recompute_engine
    ]
  end

  defp required_inputs_for_semantics(:compare) do
    [
      :observed_limit_event_read_path,
      :recomputed_limit_analysis_path,
      :comparison_frame_contract,
      :divergence_warning_policy
    ]
  end

  defp required_inputs_for_semantics(_semantics_mode), do: [:supported_limit_semantics_mode]

  defp future_capability_for_semantics(:current), do: :current_limit_analysis
  defp future_capability_for_semantics(:recomputed), do: :recomputed_limit_analysis
  defp future_capability_for_semantics(:compare), do: :limit_comparison_analysis
  defp future_capability_for_semantics(_semantics_mode), do: :limit_semantics_extension

  defp required_request_context(%PlannedSourceRequest{} = request, key) do
    case request_context_value(request, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _other ->
        {:warning,
         %ResolveWarning{
           code: missing_context_code(key),
           severity: :error,
           scope: :dashboard,
           message: "Limits source request is missing required context",
           details: %{required_context: key}
         }}
    end
  end

  defp missing_context_code(:organization_id), do: :missing_tenant_context
  defp missing_context_code(:mission_id), do: :missing_mission_context

  defp request_context_value(%PlannedSourceRequest{organization_id: value}, :organization_id)
       when is_binary(value) and value != "",
       do: value

  defp request_context_value(%PlannedSourceRequest{mission_id: value}, :mission_id)
       when is_binary(value) and value != "",
       do: value

  defp request_context_value(%PlannedSourceRequest{} = request, key) do
    context_value(request.scope_context, key)
  end

  defp requested_product(%PlannedSourceRequest{} = request) do
    product =
      request
      |> sampling_products()
      |> List.first()
      |> case do
        nil -> product_for_mode(sampling_mode(request))
        value -> normalize_atom(value)
      end

    if product in @supported_products do
      {:ok, product}
    else
      {:warning,
       warning(
         request,
         :unsupported_limits_product,
         :warning,
         "Limits source supports latest state, event history, definition interval, and analysis bucket products only",
         %{requested_product: product, supported_products: @supported_products}
       )}
    end
  end

  defp sampling_products(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :products) do
      products when is_list(products) -> products
      product when not is_nil(product) -> [product]
      _other -> []
    end
  end

  defp product_for_mode(mode) when mode in [:latest_state, :latest], do: :latest_state
  defp product_for_mode(:event_history), do: :event_history
  defp product_for_mode(:analysis_buckets), do: :analysis_buckets
  defp product_for_mode(:intervals), do: :definition_intervals
  defp product_for_mode(:definition_intervals), do: :definition_intervals
  defp product_for_mode(mode), do: mode

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details: Map.put(details, :source_request_id, request.request_id),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    with :error <- Map.fetch(context, key),
         :error <- Map.fetch(context, Atom.to_string(key)) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp context_value(_context, _key), do: nil

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> value
  end

  defp normalize_atom(value), do: value
end
