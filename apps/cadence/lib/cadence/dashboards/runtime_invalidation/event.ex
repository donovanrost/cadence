defmodule Cadence.Dashboards.RuntimeInvalidation.Event do
  @moduledoc """
  Normalized dashboard runtime invalidation event.

  Boundary functions build this struct once after cache invalidation completes,
  then use it for telemetry, PubSub, runtime-health diagnostics, and dashboard
  relevance checks. The struct is intentionally domain-shaped; adapter/runtime
  internals such as the cache server stay outside the event.
  """

  @type boundary ::
          :dashboard_version_changed
          | :catalog_revision_changed
          | :limit_definition_changed
          | :data_source_binding_changed
          | :source_watermark_changed
          | :historical_data_changed
          | :telemetry_revision_state_changed
          | :source_health_changed
          | :events_changed

  @type layer :: :plan | :source_result | :frame
  @type refresh_action ::
          :refresh_plan
          | :refresh_source_result
          | :wait_for_source_health
          | :refresh_runtime_artifacts

  @type t :: %__MODULE__{
          boundary: boundary(),
          domain_fact: atom(),
          layers: [layer()],
          filters: map(),
          layer_filters: %{optional(layer()) => map()},
          measurements: map(),
          occurred_at: DateTime.t()
        }

  @enforce_keys [
    :boundary,
    :domain_fact,
    :layers,
    :filters,
    :layer_filters,
    :measurements,
    :occurred_at
  ]
  defstruct @enforce_keys

  @known_boundaries [
    :dashboard_version_changed,
    :catalog_revision_changed,
    :limit_definition_changed,
    :data_source_binding_changed,
    :source_watermark_changed,
    :historical_data_changed,
    :telemetry_revision_state_changed,
    :source_health_changed,
    :events_changed
  ]

  @known_layers [:plan, :source_result, :frame]

  @refresh_actions %{
    dashboard_version_changed: :refresh_plan,
    catalog_revision_changed: :refresh_plan,
    data_source_binding_changed: :refresh_plan,
    limit_definition_changed: :refresh_source_result,
    source_watermark_changed: :refresh_source_result,
    historical_data_changed: :refresh_source_result,
    telemetry_revision_state_changed: :refresh_source_result,
    events_changed: :refresh_source_result
  }

  @source_health_wait_states [:degraded, :unavailable, :unknown]

  @doc """
  Runtime action a dashboard should consider for a normalized invalidation event.

  This is an operator/runtime taxonomy, not an authorization decision. Relevance
  checks still decide whether the event applies to the active dashboard context.
  """
  @spec refresh_action(t() | map()) :: refresh_action()
  def refresh_action(%__MODULE__{boundary: :source_health_changed, filters: filters}) do
    if source_health_wait_state?(get_attr(filters, :source_health)) do
      :wait_for_source_health
    else
      :refresh_source_result
    end
  end

  def refresh_action(%__MODULE__{boundary: boundary}) do
    Map.get(@refresh_actions, boundary, :refresh_runtime_artifacts)
  end

  def refresh_action(event) when is_map(event) do
    case from_recent_event(event) do
      {:ok, %__MODULE__{} = normalized_event} -> refresh_action(normalized_event)
      :error -> :refresh_runtime_artifacts
    end
  end

  @spec new(atom(), [layer()], map(), map(), map(), keyword()) :: t()
  def new(boundary, layers, filters, layer_filters, measurements, opts \\ [])
      when is_atom(boundary) and is_list(layers) and is_map(filters) and is_map(layer_filters) and
             is_map(measurements) do
    %__MODULE__{
      boundary: boundary,
      domain_fact: Keyword.get(opts, :domain_fact, boundary),
      layers: layers,
      filters: filters,
      layer_filters: layer_filters,
      measurements: normalize_measurements(measurements),
      occurred_at: Keyword.get_lazy(opts, :occurred_at, &DateTime.utc_now/0)
    }
  end

  @spec from_metadata(map(), map(), keyword()) :: {:ok, t()} | :error
  def from_metadata(metadata, measurements, opts \\ [])

  def from_metadata(metadata, measurements, opts)
      when is_map(metadata) and is_map(measurements) and is_list(opts) do
    with {:ok, boundary} <- normalize_boundary(get_attr(metadata, :boundary)),
         {:ok, domain_fact} <-
           normalize_boundary(get_attr(metadata, :domain_fact) || boundary),
         {:ok, layers} <- normalize_layers(get_attr(metadata, :layers)) do
      {:ok,
       new(
         boundary,
         layers,
         map_value(get_attr(metadata, :filters)),
         normalize_layer_filters(get_attr(metadata, :layer_filters)),
         measurements,
         domain_fact: domain_fact,
         occurred_at: occurred_at(metadata, opts)
       )}
    else
      _error -> :error
    end
  end

  def from_metadata(_metadata, _measurements, _opts), do: :error

  @spec from_recent_event(map()) :: {:ok, t()} | :error
  def from_recent_event(%{runtime_event: %__MODULE__{} = event}), do: {:ok, event}

  def from_recent_event(
        %{
          source: :dashboards_runtime_invalidation,
          event: event_type,
          metadata: metadata,
          measurements: measurements
        } = recent_event
      )
      when event_type in [:invalidate, "invalidate"] do
    from_metadata(metadata, measurements, occurred_at: get_attr(recent_event, :observed_at))
  end

  def from_recent_event(
        %{
          "event" => event_type,
          source: :dashboards_runtime_invalidation,
          metadata: metadata,
          measurements: measurements
        } = recent_event
      )
      when event_type in [:invalidate, "invalidate"] do
    from_metadata(metadata, measurements, occurred_at: get_attr(recent_event, :observed_at))
  end

  def from_recent_event(
        %{
          source: :dashboards_runtime_invalidation,
          metadata: metadata,
          measurements: measurements
        } = recent_event
      )
      when not is_map_key(recent_event, :event) and not is_map_key(recent_event, "event") do
    from_metadata(metadata, measurements, occurred_at: get_attr(recent_event, :observed_at))
  end

  def from_recent_event(_event), do: :error

  @doc """
  Stable diagnostic id for correlating invalidation and decision events.

  This is not a durable database id; it is a runtime-health correlation key built
  from the normalized invalidation event fields that are emitted in both
  invalidation and decision telemetry.
  """
  @spec id(t()) :: binary()
  def id(%__MODULE__{} = event) do
    [
      event.boundary,
      get_attr(event.filters, :mission_id),
      get_attr(event.filters, :observable),
      get_attr(event.measurements, :total),
      DateTime.to_iso8601(event.occurred_at)
    ]
    |> Enum.map_join("-", &id_value/1)
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end

  @spec to_telemetry_metadata(t(), term()) :: map()
  def to_telemetry_metadata(%__MODULE__{} = event, runtime_cache) do
    event
    |> Map.from_struct()
    |> Map.put(:runtime_cache, runtime_cache)
  end

  defp normalize_measurements(measurements) do
    plans = non_negative_integer(get_attr(measurements, :plans), 0)
    source_results = non_negative_integer(get_attr(measurements, :source_results), 0)
    frames = non_negative_integer(get_attr(measurements, :frames), 0)
    total = non_negative_integer(get_attr(measurements, :total), plans + source_results + frames)

    measurements
    |> Map.put(:plans, plans)
    |> Map.put(:source_results, source_results)
    |> Map.put(:frames, frames)
    |> Map.put(:total, total)
  end

  defp normalize_boundary(boundary) when boundary in @known_boundaries, do: {:ok, boundary}

  defp normalize_boundary(boundary) when is_binary(boundary) do
    Enum.find_value(@known_boundaries, :error, fn known_boundary ->
      if Atom.to_string(known_boundary) == boundary, do: {:ok, known_boundary}
    end)
  end

  defp normalize_boundary(_boundary), do: :error

  defp normalize_layers(nil), do: {:ok, []}

  defp normalize_layers(layers) when is_list(layers) do
    layers =
      layers
      |> Enum.map(&normalize_layer/1)
      |> Enum.reject(&is_nil/1)

    {:ok, layers}
  end

  defp normalize_layers(_layers), do: :error

  defp normalize_layer(layer) when layer in @known_layers, do: layer

  defp normalize_layer(layer) when is_binary(layer) do
    Enum.find(@known_layers, &(Atom.to_string(&1) == layer))
  end

  defp normalize_layer(_layer), do: nil

  defp source_health_wait_state?(state) when state in @source_health_wait_states, do: true

  defp source_health_wait_state?(state) when is_binary(state) do
    Enum.any?(@source_health_wait_states, &(Atom.to_string(&1) == state))
  end

  defp source_health_wait_state?(_state), do: false

  defp map_value(value) when is_map(value), do: value
  defp map_value(_value), do: %{}

  defp normalize_layer_filters(value) when is_map(value) do
    Map.new(value, fn {layer, filters} ->
      {normalize_layer(layer) || layer, map_value(filters)}
    end)
  end

  defp normalize_layer_filters(_value), do: %{}

  defp get_attr(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp occurred_at(metadata, opts) do
    get_attr(metadata, :occurred_at) || Keyword.get(opts, :occurred_at) || DateTime.utc_now()
  end

  defp id_value(nil), do: "-"
  defp id_value(value) when is_boolean(value), do: to_string(value)
  defp id_value(value) when is_integer(value), do: Integer.to_string(value)
  defp id_value(value) when is_float(value), do: Float.to_string(value)
  defp id_value(value) when is_atom(value), do: Atom.to_string(value)
  defp id_value(value) when is_binary(value), do: value
  defp id_value(value), do: inspect(value)

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default
end
