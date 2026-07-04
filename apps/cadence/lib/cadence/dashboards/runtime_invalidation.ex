defmodule Cadence.Dashboards.RuntimeInvalidation do
  @moduledoc """
  Dashboard-facing runtime cache invalidation boundary.

  Domain event producers should call this module instead of reaching into
  `RuntimeCache` layer details directly. The functions here intentionally map
  domain-shaped changes to the cache layers currently affected by that change.
  A future event bus can call these same functions from event handlers.
  """

  alias Cadence.Dashboards.RuntimeCache
  alias Cadence.Dashboards.RuntimeInvalidation.Event

  @pubsub Cadence.PubSub
  @telemetry_event [:cadence, :dashboards, :runtime_invalidation, :invalidate]
  @decision_telemetry_event [:cadence, :dashboards, :runtime_invalidation, :decision]
  @message_tag :dashboard_runtime_invalidated

  @type filters :: keyword() | map()
  @type time_range :: %{
          optional(:axis) => atom() | binary(),
          optional(:from) => DateTime.t() | binary(),
          optional(:to) => DateTime.t() | binary(),
          optional(:start) => DateTime.t() | binary(),
          optional(:end) => DateTime.t() | binary(),
          optional(:start_time) => DateTime.t() | binary(),
          optional(:end_time) => DateTime.t() | binary()
        }

  @type historical_data_change :: %{
          optional(:organization_id) => binary(),
          optional(:mission_id) => binary(),
          optional(:logical_source) => atom(),
          optional(:source_id) => binary(),
          optional(:data_source_id) => binary(),
          optional(:binding_id) => binary(),
          optional(:source_binding_id) => binary(),
          optional(:realm) => atom() | binary(),
          optional(:dataset) => binary(),
          optional(:observable) => binary(),
          optional(:replay_run_id) => binary(),
          optional(:time_range) => time_range(),
          optional(:reason) => atom() | binary(),
          optional(:revision) => binary(),
          optional(:observation_identity_id) => binary(),
          optional(:telemetry_revision_dependency) => map(),
          optional(:evidence_ref) => map()
        }

  @type source_health_change :: %{
          optional(:organization_id) => binary(),
          optional(:mission_id) => binary(),
          optional(:logical_source) => atom(),
          optional(:source_id) => binary(),
          optional(:data_source_id) => binary(),
          optional(:binding_id) => binary(),
          optional(:source_binding_id) => binary(),
          optional(:realm) => atom() | binary(),
          optional(:dataset) => binary(),
          optional(:observable) => binary(),
          optional(:source_health) => atom() | binary(),
          optional(:previous_source_health) => atom() | binary(),
          optional(:reason) => atom() | binary(),
          optional(:observed_at) => DateTime.t() | binary(),
          optional(:evidence_ref) => map()
        }

  @type result :: %{
          plans: non_neg_integer(),
          source_results: non_neg_integer(),
          frames: non_neg_integer()
        }

  @type invalidation_event :: Event.t()

  @type coverage_row :: %{
          domain_fact: atom(),
          boundary: atom(),
          layers: [atom()],
          default_cache_policy: atom() | nil,
          producer_status: :wired | :boundary_ready,
          producer: binary(),
          notes: binary()
        }

  @plan_filter_keys [
    :dashboard_id,
    :organization_id,
    :mission_id,
    :document_version,
    :document_schema_version,
    :widget_registry_version,
    :source_capability_version,
    :logical_source,
    :observable
  ]

  @source_result_filter_keys [
    :request_id,
    :cache_policy,
    :organization_id,
    :mission_id,
    :logical_source,
    :observable,
    :time_range,
    :source_binding_id,
    :data_source_id,
    :realm,
    :dataset,
    :replay_run_id,
    :observation_identity_id,
    :telemetry_revision_dependency,
    :watermark_cursor,
    :watermark_confidence,
    :watermark_freshness_state
  ]

  @frame_filter_keys [
    :cache_policy,
    :source_result_fingerprint,
    :placement_id,
    :placement_size,
    :display,
    :frame_shape,
    :limit_context,
    :catalog_revision,
    :request_id,
    :organization_id,
    :mission_id,
    :logical_source,
    :observable,
    :time_range,
    :source_binding_id,
    :data_source_id,
    :realm,
    :dataset,
    :replay_run_id,
    :observation_identity_id,
    :telemetry_revision_dependency
  ]

  @coverage_matrix [
    %{
      domain_fact: :dashboard_version_changed,
      boundary: :dashboard_version_changed,
      layers: [:plan],
      default_cache_policy: nil,
      producer_status: :wired,
      producer: "Cadence.Dashboards.DocumentStore",
      notes: "Document writes invalidate plan artifacts for the affected dashboard/version scope."
    },
    %{
      domain_fact: :catalog_revision_changed,
      boundary: :catalog_revision_changed,
      layers: [:plan, :source_result, :frame],
      default_cache_policy: nil,
      producer_status: :wired,
      producer: "Cadence.Catalog",
      notes: "Catalog revision import invalidates scoped semantic plan/source/frame artifacts."
    },
    %{
      domain_fact: :limit_definition_changed,
      boundary: :limit_definition_changed,
      layers: [:plan, :source_result, :frame],
      default_cache_policy: nil,
      producer_status: :wired,
      producer: "Cadence.Governance",
      notes: "Limit lifecycle changes default to the limits logical source."
    },
    %{
      domain_fact: :data_source_binding_changed,
      boundary: :data_source_binding_changed,
      layers: [:plan, :source_result, :frame],
      default_cache_policy: nil,
      producer_status: :wired,
      producer: "Cadence.Dashboards.DataSources",
      notes: "Data-source and binding upserts invalidate source-bound runtime artifacts."
    },
    %{
      domain_fact: :source_watermark_changed,
      boundary: :source_watermark_changed,
      layers: [:source_result, :frame],
      default_cache_policy: :live,
      producer_status: :wired,
      producer: "Cadence.Telemetry.Storage",
      notes:
        "Telemetry writes invalidate live source/frame artifacts for affected source identity."
    },
    %{
      domain_fact: :historical_data_changed,
      boundary: :historical_data_changed,
      layers: [:source_result, :frame],
      default_cache_policy: :snapshot,
      producer_status: :wired,
      producer: "Cadence.Telemetry.Storage",
      notes:
        "Telemetry writes invalidate overlapping snapshot artifacts for corrections/backfills."
    },
    %{
      domain_fact: :telemetry_revision_state_changed,
      boundary: :telemetry_revision_state_changed,
      layers: [:source_result, :frame],
      default_cache_policy: nil,
      producer_status: :wired,
      producer: "Cadence.Telemetry.Storage.ObservationIdentityStates",
      notes:
        "Observation identity state changes invalidate source/frame artifacts whose revision badges depend on the affected identity."
    },
    %{
      domain_fact: :source_health_changed,
      boundary: :source_health_changed,
      layers: [:source_result, :frame],
      default_cache_policy: :live,
      producer_status: :wired,
      producer: "Cadence.Dashboards.SourceHealth",
      notes:
        "Dashboard source-health transitions invalidate live source/frame artifacts for affected source identity."
    },
    %{
      domain_fact: :events_changed,
      boundary: :events_changed,
      layers: [:source_result, :frame],
      default_cache_policy: :live,
      producer_status: :wired,
      producer: "Cadence.Contacts",
      notes:
        "Contact interval and mission timeline mutations invalidate live events source/frame artifacts."
    }
  ]

  @doc """
  Runtime invalidation coverage matrix.

  The matrix is a compact contract for which domain facts are expected to call
  which dashboard invalidation boundary. `:boundary_ready` means the cache
  invalidation function and tests exist, but the durable domain producer is not
  implemented yet.
  """
  @spec coverage_matrix() :: [coverage_row()]
  def coverage_matrix do
    @coverage_matrix
  end

  @doc """
  Telemetry event emitted after each runtime invalidation boundary call.
  """
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry_event

  @doc """
  Telemetry event emitted by dashboard runtimes after evaluating invalidation relevance.
  """
  @spec decision_telemetry_event() :: [atom()]
  def decision_telemetry_event, do: @decision_telemetry_event

  @doc """
  Emit a dashboard-local invalidation relevance decision.

  The invalidation boundary event records the producer/cache fact. This decision
  event records what one open dashboard runtime did with that fact for its
  active runtime context.
  """
  @spec emit_decision(Event.t(), map(), keyword()) :: :ok
  def emit_decision(%Event{} = event, decision, opts \\ []) when is_map(decision) do
    measurements = %{total: 1}

    metadata =
      event
      |> Event.to_telemetry_metadata(Keyword.get(opts, :runtime_cache, RuntimeCache))
      |> Map.put(:invalidation_event_id, Keyword.get(opts, :invalidation_event_id))
      |> Map.put(:decision, decision)
      |> Map.merge(Map.take(decision, decision_metadata_keys()))

    :telemetry.execute(@decision_telemetry_event, measurements, metadata)
  end

  @doc """
  Subscribe the caller to runtime invalidations relevant to a dashboard scope.

  Dashboard views subscribe at the organization, mission, and dashboard levels
  so broad invalidations can still wake an open dashboard without every producer
  needing to know the dashboard id.
  """
  @spec subscribe(filters()) :: :ok | {:error, term()}
  def subscribe(filters) do
    filters
    |> normalize_filters()
    |> subscription_topics()
    |> subscribe_topics()
  end

  @doc """
  PubSub topic for organization-scoped runtime invalidations.
  """
  @spec organization_topic(binary()) :: binary()
  def organization_topic(organization_id) when is_binary(organization_id) do
    "dashboards:runtime_invalidation:org:#{organization_id}"
  end

  @doc """
  PubSub topic for mission-scoped runtime invalidations.
  """
  @spec mission_topic(binary(), binary()) :: binary()
  def mission_topic(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    "dashboards:runtime_invalidation:org:#{organization_id}:mission:#{mission_id}"
  end

  @doc """
  PubSub topic for dashboard-scoped runtime invalidations.
  """
  @spec dashboard_topic(binary(), binary(), binary()) :: binary()
  def dashboard_topic(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    "dashboards:runtime_invalidation:org:#{organization_id}:mission:#{mission_id}:dashboard:#{dashboard_id}"
  end

  @doc """
  Invalidate dashboard plan artifacts when a dashboard version/document changes.

  Source-result and frame caches are keyed by resolved source and frame identity,
  not dashboard id, so this boundary currently invalidates only plan entries.
  """
  @spec dashboard_version_changed(filters(), keyword()) :: result()
  def dashboard_version_changed(filters, opts \\ []) do
    invalidate_boundary(:dashboard_version_changed, [:plan], filters, opts)
  end

  @doc """
  Invalidate caches affected by catalog revision activation or supersession.

  Frame entries can match `:catalog_revision` directly. Plan and source-result
  entries do not currently store catalog revision, so they are invalidated only
  by any compatible scope filters supplied with the change, such as mission or
  logical source.
  """
  @spec catalog_revision_changed(filters(), keyword()) :: result()
  def catalog_revision_changed(filters, opts \\ []) do
    invalidate_boundary(:catalog_revision_changed, [:plan, :source_result, :frame], filters, opts)
  end

  @doc """
  Invalidate dashboard artifacts affected by a limits definition lifecycle change.
  """
  @spec limit_definition_changed(filters(), keyword()) :: result()
  def limit_definition_changed(filters, opts \\ []) do
    filters = put_default_filter(filters, :logical_source, :limits)
    invalidate_boundary(:limit_definition_changed, [:plan, :source_result, :frame], filters, opts)
  end

  @doc """
  Invalidate dashboard artifacts affected by a source/data binding change.
  """
  @spec data_source_binding_changed(filters(), keyword()) :: result()
  def data_source_binding_changed(filters, opts \\ []) do
    invalidate_boundary(
      :data_source_binding_changed,
      [:plan, :source_result, :frame],
      filters,
      opts
    )
  end

  @doc """
  Invalidate archive snapshot artifacts affected by historical data mutation.

  This boundary is for backfills, corrections, reprocessed packet batches, and
  similar data-management events. It defaults to snapshot cache entries because
  live cache entries are already freshness/watermark-bound. Producers can pass
  `:cache_policy` explicitly if they need a broader or different invalidation.

  Supported identity filters include `:data_source_id`/`:source_id`,
  `:source_binding_id`/`:binding_id`, `:logical_source`, `:observable`, and a
  `:time_range` map. Time ranges invalidate source-result and frame entries only
  when the changed interval overlaps the request interval recorded on the entry.
  `:reason`, `:revision`, and `:evidence_ref` are intentionally audit context,
  not cache-match filters.
  """
  @spec historical_data_changed(filters() | historical_data_change(), keyword()) :: result()
  def historical_data_changed(filters, opts \\ []) do
    filters = put_default_filter(filters, :cache_policy, :snapshot)
    invalidate_boundary(:historical_data_changed, [:source_result, :frame], filters, opts)
  end

  @doc """
  Invalidate dashboard artifacts affected by a source watermark transition.
  """
  @spec source_watermark_changed(filters(), keyword()) :: result()
  def source_watermark_changed(filters, opts \\ []) do
    filters = put_default_filter(filters, :cache_policy, :live)
    invalidate_boundary(:source_watermark_changed, [:source_result, :frame], filters, opts)
  end

  @doc """
  Invalidate dashboard artifacts affected by telemetry observation identity state changes.

  This boundary is for duplicate, conflict, correction, supersession, advisory,
  and future resolution workflows that change the identity-state projection even
  when no new TSDB sample row is appended. It intentionally does not default a
  cache policy because revision-state enrichment can affect both live and
  snapshot source/frame artifacts.
  """
  @spec telemetry_revision_state_changed(filters() | historical_data_change(), keyword()) ::
          result()
  def telemetry_revision_state_changed(filters, opts \\ []) do
    filters = put_default_filter(filters, :logical_source, :telemetry)

    invalidate_boundary(
      :telemetry_revision_state_changed,
      [:source_result, :frame],
      filters,
      opts
    )
  end

  @doc """
  Invalidate live dashboard source artifacts affected by source health changes.

  Source health is a live fact used by source-result preflight. The current
  health value is audit context, not a cache-match filter; callers should scope
  invalidation by source identity such as `:data_source_id`, `:source_binding_id`,
  `:logical_source`, `:mission_id`, or `:observable`.
  """
  @spec source_health_changed(filters() | source_health_change(), keyword()) :: result()
  def source_health_changed(filters, opts \\ []) do
    filters = put_default_filter(filters, :cache_policy, :live)
    invalidate_boundary(:source_health_changed, [:source_result, :frame], filters, opts)
  end

  @doc """
  Invalidate live dashboard event overlays affected by contact or mission-event changes.

  Event overlays are source-backed but not live-polled every dashboard tick.
  Producers should call this boundary when contact intervals or mission
  timeline rows change so open dashboards refresh the events source on demand.
  """
  @spec events_changed(filters(), keyword()) :: result()
  def events_changed(filters, opts \\ []) do
    filters =
      filters
      |> put_default_filter(:cache_policy, :live)
      |> put_default_filter(:logical_source, :events)

    invalidate_boundary(:events_changed, [:source_result, :frame], filters, opts)
  end

  defp invalidate_boundary(boundary, layers, filters, opts) do
    started_at = System.monotonic_time()
    filters = normalize_filters(filters)
    result = invalidate_layers(layers, filters, opts)
    duration = System.monotonic_time() - started_at
    event = build_event(boundary, layers, filters, result, duration)

    emit_invalidation(event, opts)
    broadcast_invalidation(event)

    result
  end

  defp invalidate_layers(layers, filters, opts) do
    server = Keyword.get(opts, :runtime_cache, RuntimeCache)

    Enum.reduce(layers, empty_result(), fn layer, result ->
      layer_filters = layer_filters(layer, filters)
      count = invalidate_layer(layer, server, layer_filters)
      Map.update!(result, result_key(layer), &(&1 + count))
    end)
  end

  defp invalidate_layer(_layer, _server, filters) when map_size(filters) == 0, do: 0

  defp invalidate_layer(:plan, server, filters) do
    {:ok, count} = RuntimeCache.invalidate_plans(server, filters)
    count
  end

  defp invalidate_layer(:source_result, server, filters) do
    {:ok, count} = RuntimeCache.invalidate_source_results(server, filters)
    count
  end

  defp invalidate_layer(:frame, server, filters) do
    {:ok, count} = RuntimeCache.invalidate_frames(server, filters)
    count
  end

  defp layer_filters(:plan, filters), do: Map.take(filters, @plan_filter_keys)
  defp layer_filters(:source_result, filters), do: Map.take(filters, @source_result_filter_keys)
  defp layer_filters(:frame, filters), do: Map.take(filters, @frame_filter_keys)

  defp result_key(:plan), do: :plans
  defp result_key(:source_result), do: :source_results
  defp result_key(:frame), do: :frames

  defp empty_result, do: %{plans: 0, source_results: 0, frames: 0}

  defp build_event(boundary, layers, filters, result, duration) do
    Event.new(
      boundary,
      layers,
      filters,
      layer_filters_by_layer(layers, filters),
      %{
        plans: result.plans,
        source_results: result.source_results,
        frames: result.frames,
        total: result.plans + result.source_results + result.frames,
        duration: duration
      }
    )
  end

  defp emit_invalidation(%Event{} = event, opts) do
    :telemetry.execute(
      @telemetry_event,
      event.measurements,
      Event.to_telemetry_metadata(event, Keyword.get(opts, :runtime_cache, RuntimeCache))
    )
  end

  defp decision_metadata_keys do
    [
      :dashboard_id,
      :organization_id,
      :mission_id,
      :matches?,
      :dashboard_matches?,
      :context_matches?,
      :context_reason,
      :refresh_allowed?,
      :refresh_reason,
      :affected_placement_count,
      :affected_placement_ids,
      :affected_widget_type_ids,
      :affected_impact_reasons,
      :decision_status
    ]
  end

  defp broadcast_invalidation(%Event{} = event) do
    if is_nil(Process.whereis(@pubsub)) do
      :ok
    else
      do_broadcast_invalidation(event)
    end
  end

  defp do_broadcast_invalidation(%Event{} = event) do
    event.filters
    |> broadcast_topics()
    |> Enum.each(fn topic ->
      Phoenix.PubSub.broadcast(@pubsub, topic, {@message_tag, event})
    end)

    :ok
  end

  defp subscribe_topics([]), do: :ok

  defp subscribe_topics(topics) do
    Enum.reduce_while(topics, :ok, fn topic, :ok ->
      case Phoenix.PubSub.subscribe(@pubsub, topic) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp subscription_topics(filters) do
    [
      organization_subscription_topic(filters),
      mission_subscription_topic(filters),
      dashboard_subscription_topic(filters)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp broadcast_topics(filters) do
    cond do
      topic = dashboard_subscription_topic(filters) ->
        [topic]

      topic = mission_subscription_topic(filters) ->
        [topic]

      topic = organization_subscription_topic(filters) ->
        [topic]

      true ->
        []
    end
  end

  defp organization_subscription_topic(%{organization_id: organization_id})
       when is_binary(organization_id) do
    organization_topic(organization_id)
  end

  defp organization_subscription_topic(_filters), do: nil

  defp mission_subscription_topic(%{organization_id: organization_id, mission_id: mission_id})
       when is_binary(organization_id) and is_binary(mission_id) do
    mission_topic(organization_id, mission_id)
  end

  defp mission_subscription_topic(_filters), do: nil

  defp dashboard_subscription_topic(%{
         organization_id: organization_id,
         mission_id: mission_id,
         dashboard_id: dashboard_id
       })
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    dashboard_topic(organization_id, mission_id, dashboard_id)
  end

  defp dashboard_subscription_topic(_filters), do: nil

  defp layer_filters_by_layer(layers, filters) do
    Map.new(layers, fn layer ->
      {layer, layer_filters(layer, filters)}
    end)
  end

  defp put_default_filter(filters, key, value) do
    filters
    |> normalize_filters()
    |> Map.put_new(key, value)
  end

  defp normalize_filters(filters) when is_list(filters),
    do: filters |> Map.new() |> normalize_filters()

  defp normalize_filters(filters) when is_map(filters) do
    Map.new(filters, fn {key, value} ->
      key = normalize_key(key)
      {key, normalize_value(key, value)}
    end)
    |> reject_nil_values()
  end

  defp reject_nil_values(filters) do
    Map.reject(filters, fn {_key, value} -> is_nil(value) end)
  end

  defp normalize_key("dashboard_id"), do: :dashboard_id
  defp normalize_key("organization_id"), do: :organization_id
  defp normalize_key("mission_id"), do: :mission_id
  defp normalize_key("document_version"), do: :document_version
  defp normalize_key("lifecycle_action"), do: :lifecycle_action
  defp normalize_key("source_version"), do: :source_version
  defp normalize_key("document_schema_version"), do: :document_schema_version
  defp normalize_key("widget_registry_version"), do: :widget_registry_version
  defp normalize_key("source_capability_version"), do: :source_capability_version
  defp normalize_key("logical_source"), do: :logical_source
  defp normalize_key("observable"), do: :observable
  defp normalize_key("observation_identity_id"), do: :observation_identity_id
  defp normalize_key("telemetry_revision_dependency"), do: :telemetry_revision_dependency
  defp normalize_key("request_id"), do: :request_id
  defp normalize_key("cache_policy"), do: :cache_policy
  defp normalize_key(:source_id), do: :data_source_id
  defp normalize_key("source_id"), do: :data_source_id
  defp normalize_key(:binding_id), do: :source_binding_id
  defp normalize_key("binding_id"), do: :source_binding_id
  defp normalize_key("time_range"), do: :time_range
  defp normalize_key("source_binding_id"), do: :source_binding_id
  defp normalize_key("data_source_id"), do: :data_source_id
  defp normalize_key("realm"), do: :realm
  defp normalize_key("dataset"), do: :dataset
  defp normalize_key("watermark_cursor"), do: :watermark_cursor
  defp normalize_key("watermark_confidence"), do: :watermark_confidence
  defp normalize_key("watermark_freshness_state"), do: :watermark_freshness_state
  defp normalize_key("source_result_fingerprint"), do: :source_result_fingerprint
  defp normalize_key("placement_id"), do: :placement_id
  defp normalize_key("placement_size"), do: :placement_size
  defp normalize_key("display"), do: :display
  defp normalize_key("frame_shape"), do: :frame_shape
  defp normalize_key("limit_context"), do: :limit_context
  defp normalize_key("catalog_revision"), do: :catalog_revision
  defp normalize_key(key), do: key

  defp normalize_value(:logical_source, "telemetry"), do: :telemetry
  defp normalize_value(:logical_source, "limits"), do: :limits
  defp normalize_value(:logical_source, "events"), do: :events
  defp normalize_value(:logical_source, "operational_observables"), do: :operational_observables
  defp normalize_value(_key, value), do: value
end
