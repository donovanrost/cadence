defmodule Cadence.Dashboards.RuntimeCacheKey do
  @moduledoc """
  Stable cache-key contract for dashboard runtime layers.

  This module intentionally does not store anything. It defines the identity
  inputs that future dashboard runtime caches must include so cache storage can
  be added without smuggling freshness, source-binding, or frame-shaping
  semantics into ad hoc keys.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    Document,
    PlannedSourceRequest,
    SourceWatermark
  }

  @type layer :: :plan | :source_result | :frame

  @type t :: %__MODULE__{
          layer: layer(),
          fingerprint: binary(),
          parts: map()
        }

  defstruct [:layer, :fingerprint, parts: %{}]

  @spec fingerprint(term()) :: binary()
  def fingerprint(value) do
    value
    |> normalize()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  @spec plan(DashboardResolveRequest.t(), keyword()) :: t()
  def plan(%DashboardResolveRequest{} = request, opts \\ []) when is_list(opts) do
    new(:plan, %{
      organization_id: request.organization_id || request.document.organization_id,
      mission_id: request.mission_id || request.document.mission_id,
      dashboard_id: request.dashboard_id || request.document.dashboard_id,
      document: document_identity(request.document, opts),
      document_mode: request.document_mode,
      resolve_mode: request.resolve_mode,
      time_context: request.time_context,
      scope_context: request.scope_context,
      data_context: request.data_context,
      limit_context: request.limit_context,
      interaction_context: request.interaction_context,
      widget_registry_version: Keyword.get(opts, :widget_registry_version),
      source_capability_version: Keyword.get(opts, :source_capability_version),
      source_registry_overrides: source_registry_overrides(opts)
    })
  end

  @spec source_result(PlannedSourceRequest.t(), keyword()) :: t()
  def source_result(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    cache_policy = Keyword.get(opts, :cache_policy, :live)

    new(:source_result, %{
      cache_policy: cache_policy,
      request: request_identity(request),
      source_binding: source_binding_identity(Keyword.get(opts, :source_binding)),
      source_binding_segments: Keyword.get(opts, :source_binding_segments),
      data_source: data_source_identity(Keyword.get(opts, :data_source)),
      freshness_policy: freshness_policy(cache_policy, opts),
      watermark_cursor: watermark_cursor(cache_policy, Keyword.get(opts, :watermark)),
      data_revision: Keyword.get(opts, :data_revision),
      correction_cursor: Keyword.get(opts, :correction_cursor),
      backfill_cursor: Keyword.get(opts, :backfill_cursor)
    })
  end

  @spec frame(t(), keyword()) :: t()
  def frame(%__MODULE__{layer: :source_result} = source_result_key, opts \\ [])
      when is_list(opts) do
    new(:frame, %{
      cache_policy: Map.get(source_result_key.parts, :cache_policy, :live),
      source_result_fingerprint: source_result_key.fingerprint,
      source_result_request: Map.get(source_result_key.parts, :request),
      source_result_binding: Map.get(source_result_key.parts, :source_binding),
      source_result_binding_segments: Map.get(source_result_key.parts, :source_binding_segments),
      source_result_data_source: Map.get(source_result_key.parts, :data_source),
      placement_id: Keyword.get(opts, :placement_id),
      placement_size: Keyword.get(opts, :placement_size, %{}),
      display: Keyword.get(opts, :display, %{}),
      frame_shape: Keyword.get(opts, :frame_shape),
      limit_context: Keyword.get(opts, :limit_context),
      catalog_revision: Keyword.get(opts, :catalog_revision),
      telemetry_revision_dependency: Keyword.get(opts, :telemetry_revision_dependency)
    })
  end

  defp new(layer, parts) when layer in [:plan, :source_result, :frame] and is_map(parts) do
    %__MODULE__{
      layer: layer,
      parts: compact(parts),
      fingerprint: fingerprint({layer, parts})
    }
  end

  defp document_identity(%Document{} = document, opts) do
    %{
      dashboard_id: document.dashboard_id,
      schema_version: document.schema_version,
      document_version: Keyword.get(opts, :document_version, document_version(document)),
      document_fingerprint: fingerprint(document)
    }
  end

  defp document_version(%Document{metadata: metadata}) when is_map(metadata) do
    get_attr(metadata, :version) || get_attr(metadata, :dashboard_version)
  end

  defp request_identity(%PlannedSourceRequest{} = request) do
    %{
      request_id: request.request_id,
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      logical_source: request.logical_source,
      observables: request.observables,
      scope_context: request.scope_context,
      time_context: request.time_context,
      data_context: request.data_context,
      limit_context: request.limit_context,
      value_type: request.value_type,
      sampling: request.sampling,
      source_dependencies: request.source_dependencies,
      overlays: request.overlays
    }
  end

  defp source_registry_overrides(opts) do
    opts
    |> Keyword.take([:data_sources, :data_bindings, :adapters])
    |> Enum.into(%{})
    |> compact()
  end

  defp source_binding_identity(nil), do: nil

  defp source_binding_identity(%DataBinding{} = binding) do
    %{
      binding_id: binding.binding_id,
      organization_id: binding.organization_id,
      mission_id: binding.mission_id,
      realm: binding.realm,
      logical_source: binding.logical_source,
      data_source_id: binding.data_source_id,
      dataset: binding.dataset,
      status: binding.status,
      binding_version: binding.binding_version,
      current_event_id: binding.current_event_id,
      active_from: binding.active_from,
      active_to: binding.active_to
    }
  end

  defp data_source_identity(nil), do: nil

  defp data_source_identity(%DataSource{} = source) do
    %{
      data_source_id: source.data_source_id,
      owner: source.owner,
      kind: source.kind,
      adapter: source.adapter,
      organization_id: source.organization_id,
      mission_id: source.mission_id,
      isolation_level: source.isolation_level,
      capabilities: source.capabilities,
      metadata: source.metadata
    }
  end

  defp freshness_policy(:snapshot, _opts), do: nil
  defp freshness_policy(_cache_policy, opts), do: Keyword.get(opts, :freshness_policy, %{})

  defp watermark_cursor(:snapshot, _watermark), do: nil
  defp watermark_cursor(_cache_policy, watermark), do: watermark_cursor(watermark)

  defp watermark_cursor(nil), do: nil

  defp watermark_cursor(%SourceWatermark{} = watermark) do
    %{
      logical_source: watermark.logical_source,
      request_id: watermark.request_id,
      source_binding_id: watermark.source_binding_id,
      data_source_id: watermark.data_source_id,
      realm: watermark.realm,
      replay_run_id: watermark.replay_run_id,
      dataset: watermark.dataset,
      complete_through: watermark.complete_through,
      latest_receipt_time: watermark.latest_receipt_time,
      retention_starts_at: watermark.retention_starts_at,
      confidence: watermark.confidence,
      freshness_state: watermark.freshness_state
    }
  end

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp normalize(%_{} = value) do
    value
    |> Map.from_struct()
    |> normalize()
  end

  defp normalize(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {normalize_key(key), normalize(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp normalize(list) when is_list(list) do
    if Keyword.keyword?(list) do
      list
      |> Enum.map(fn {key, value} -> {normalize_key(key), normalize(value)} end)
      |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
    else
      Enum.map(list, &normalize/1)
    end
  end

  defp normalize(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize/1)
    |> List.to_tuple()
  end

  defp normalize(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  defp compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, to_string(key)))
  end
end
