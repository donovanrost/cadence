defmodule Cadence.Dashboards.DataLinks do
  @moduledoc """
  Builders for dashboard data links and evidence references.

  Source adapters attach these typed references to frames, fields, and warnings.
  The web layer can render or route them without needing source-specific map
  conventions.
  """

  alias Cadence.Dashboards.{DataContext, DataLink, EvidenceRef, PlannedSourceRequest}

  @spec request_context(PlannedSourceRequest.t(), binary() | nil, keyword()) :: map()
  def request_context(%PlannedSourceRequest{} = request, observable_id \\ nil, opts \\ []) do
    %{
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      observable_id: observable_id,
      scope: context_map(request.scope_context),
      time: context_map(request.time_context),
      data: request_data_context(request, opts),
      limit: context_map(request.limit_context),
      sampling: context_map(request.sampling)
    }
    |> drop_empty_values()
  end

  defp request_data_context(%PlannedSourceRequest{} = request, opts) do
    data_context = context_map(request.data_context)
    source_binding = Keyword.get(opts, :source_binding)

    data_context
    |> maybe_put(:realm, inferred_replay_realm(request))
    |> maybe_put(
      :view,
      DataContext.source_value(request.data_context, request.logical_source, :view)
    )
    |> maybe_put(
      :validity_state,
      DataContext.source_value(request.data_context, request.logical_source, :validity_state)
    )
    |> maybe_put(
      :replay_run_id,
      DataContext.source_value(request.data_context, request.logical_source, :replay_run_id)
    )
    |> maybe_put(
      :data_source_id,
      source_binding_data_source_id(source_binding) ||
        DataContext.source_value(request.data_context, request.logical_source, :data_source_id)
    )
    |> maybe_put(
      :source_binding_id,
      source_binding_id(source_binding) ||
        DataContext.source_value(request.data_context, request.logical_source, :source_binding_id)
    )
    |> maybe_put(
      :dataset,
      source_binding_dataset(source_binding) ||
        DataContext.source_value(request.data_context, request.logical_source, :dataset)
    )
  end

  @spec telemetry_point_link(PlannedSourceRequest.t(), binary() | nil, keyword()) ::
          DataLink.t() | nil
  def telemetry_point_link(%PlannedSourceRequest{} = request, observable_id, opts \\ []) do
    case string_id(observable_id) do
      nil ->
        nil

      point_id ->
        data_link(
          :telemetry_point,
          Keyword.get(opts, :label, "Telemetry point"),
          point_id,
          request_context(request, point_id, opts),
          opts
        )
    end
  end

  @spec telemetry_sample_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def telemetry_sample_links(%PlannedSourceRequest{} = request, samples, opts \\ []) do
    samples
    |> List.wrap()
    |> Enum.map(fn sample ->
      sample
      |> attr(:sample_id)
      |> string_id()
      |> case do
        nil ->
          nil

        sample_id ->
          observable_id = attr(sample, :point_id)

          data_link(
            :telemetry_sample,
            Keyword.get(opts, :label, "Telemetry sample"),
            sample_id,
            request_context(request, observable_id, opts),
            opts
          )
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec telemetry_sample_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def telemetry_sample_evidence_refs(samples) do
    samples
    |> List.wrap()
    |> Enum.map(&telemetry_sample_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec telemetry_links(PlannedSourceRequest.t(), binary() | nil, [map() | struct()], keyword()) ::
          [DataLink.t()]
  def telemetry_links(%PlannedSourceRequest{} = request, observable_id, samples, opts \\ []) do
    [
      telemetry_point_link(request, observable_id, opts)
      | telemetry_sample_links(request, samples, opts)
    ]
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec limit_links(PlannedSourceRequest.t(), binary() | nil, [map() | struct()], keyword()) ::
          [DataLink.t()]
  def limit_links(%PlannedSourceRequest{} = request, observable_id, events, opts \\ []) do
    events = List.wrap(events)

    [
      telemetry_point_link(request, observable_id, opts)
      | limit_event_links(request, events, opts) ++
          limit_definition_links(request, events, opts) ++
          telemetry_sample_links(request, events, opts)
    ]
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec limit_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def limit_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.map(&limit_event_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec limit_definition_interval_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def limit_definition_interval_evidence_refs(intervals) do
    intervals
    |> List.wrap()
    |> Enum.flat_map(&limit_definition_interval_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec operational_interval_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def operational_interval_evidence_refs(intervals, opts \\ []) do
    source = Keyword.get(opts, :source, :events)

    intervals
    |> List.wrap()
    |> Enum.flat_map(&operational_interval_evidence_refs_for(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec mission_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def mission_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.map(fn event ->
      event
      |> attr(:mission_event_id)
      |> string_id()
      |> case do
        nil ->
          nil

        event_id ->
          data_link(
            :mission_event,
            Keyword.get(opts, :label, "Mission event"),
            event_id,
            request_context(request, attr(event, :subject_id), opts),
            opts
          )
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec operational_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) :: [
          DataLink.t()
        ]
  def operational_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.map(fn event ->
      event
      |> attr(:source_event_id)
      |> string_id()
      |> event_link(
        :operational_event,
        Keyword.get(opts, :label, "Operational event"),
        request_context(request, operational_event_subject_id(event), opts),
        opts
      )
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec operational_event_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def operational_event_evidence_refs(events, opts \\ []) do
    source = Keyword.get(opts, :source, :events)

    events
    |> List.wrap()
    |> Enum.map(&operational_event_evidence_ref(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec mission_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def mission_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&mission_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_health_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def source_health_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      context = request_context(request, attr(event, :source_health_key), opts)

      [
        event
        |> attr(:source_health_event_id)
        |> string_id()
        |> event_link(:source_health_event, "Source health event", context, opts),
        operational_event_link(
          request,
          :source_health_event,
          attr(event, :source_health_event_id),
          attr(event, :source_health_key),
          opts,
          attr(event, :replay_run_id)
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec source_health_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def source_health_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&source_health_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_watermark_event_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) ::
          [DataLink.t()]
  def source_watermark_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      context = request_context(request, attr(event, :source_watermark_key), opts)

      [
        event
        |> attr(:source_watermark_event_id)
        |> string_id()
        |> event_link(:source_watermark_event, "Source watermark event", context, opts),
        operational_event_link(
          request,
          :source_watermark_event,
          attr(event, :source_watermark_event_id),
          attr(event, :source_watermark_key),
          opts,
          attr(event, :replay_run_id)
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec source_watermark_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def source_watermark_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&source_watermark_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_capability_posture_event_links(
          PlannedSourceRequest.t(),
          [map() | struct()],
          keyword()
        ) ::
          [DataLink.t()]
  def source_capability_posture_event_links(%PlannedSourceRequest{} = request, events, opts \\ []) do
    events
    |> List.wrap()
    |> Enum.map(fn event ->
      operational_event_link(
        request,
        :source_capability_posture,
        source_capability_posture_operational_event_id(event),
        source_capability_posture_subject_id(event),
        opts
      )
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec source_capability_posture_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def source_capability_posture_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.map(&source_capability_posture_event_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_binding_interval_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def source_binding_interval_evidence_refs(intervals, opts \\ []) do
    source = Keyword.get(opts, :source)

    intervals
    |> List.wrap()
    |> Enum.flat_map(&source_binding_interval_evidence_refs_for(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec telemetry_revision_decision_event_links(
          PlannedSourceRequest.t(),
          [map() | struct()],
          keyword()
        ) :: [DataLink.t()]
  def telemetry_revision_decision_event_links(
        %PlannedSourceRequest{} = request,
        events,
        opts \\ []
      ) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      subject_id = attr(event, :observable_id) || attr(event, :point_id)
      context = request_context(request, subject_id, opts)

      [
        event
        |> attr(:decision_event_id)
        |> string_id()
        |> event_link(
          :telemetry_revision_decision_event,
          "Telemetry revision decision event",
          context,
          opts
        ),
        operational_event_link(
          request,
          :telemetry_observation_identity_decision_event,
          attr(event, :decision_event_id),
          subject_id,
          opts
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec telemetry_revision_decision_event_evidence_refs([map() | struct()]) :: [
          EvidenceRef.t()
        ]
  def telemetry_revision_decision_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&telemetry_revision_decision_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec telemetry_backfill_lifecycle_event_links(
          PlannedSourceRequest.t(),
          [map() | struct()],
          keyword()
        ) :: [DataLink.t()]
  def telemetry_backfill_lifecycle_event_links(
        %PlannedSourceRequest{} = request,
        events,
        opts \\ []
      ) do
    events
    |> List.wrap()
    |> Enum.flat_map(fn event ->
      subject_id = attr(event, :observable_id) || attr(event, :point_id)
      context = request_context(request, subject_id, opts)

      [
        event
        |> attr(:backfill_lifecycle_event_id)
        |> string_id()
        |> event_link(
          :telemetry_backfill_lifecycle_event,
          "Telemetry backfill lifecycle event",
          context,
          opts
        ),
        operational_event_link(
          request,
          :telemetry_backfill_lifecycle_event,
          attr(event, :backfill_lifecycle_event_id),
          subject_id,
          opts
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec telemetry_backfill_lifecycle_event_evidence_refs([map() | struct()]) :: [
          EvidenceRef.t()
        ]
  def telemetry_backfill_lifecycle_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&telemetry_backfill_lifecycle_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec contact_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) :: [DataLink.t()]
  def contact_links(%PlannedSourceRequest{} = request, contacts, opts \\ []) do
    contacts
    |> List.wrap()
    |> Enum.map(fn contact ->
      contact
      |> contact_id()
      |> string_id()
      |> case do
        nil ->
          nil

        contact_id ->
          data_link(
            :contact,
            Keyword.get(opts, :label, "Contact"),
            contact_id,
            request_context(request, contact_id, opts),
            opts
          )
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec operational_resource_links(PlannedSourceRequest.t(), [map() | struct()], keyword()) :: [
          DataLink.t()
        ]
  def operational_resource_links(%PlannedSourceRequest{} = request, rows, opts \\ []) do
    rows
    |> List.wrap()
    |> Enum.flat_map(&operational_resource_row_links(request, &1, opts))
    |> Enum.reject(&is_nil/1)
    |> dedupe_links()
  end

  @spec contact_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def contact_evidence_refs(contacts) do
    contacts
    |> List.wrap()
    |> Enum.map(&contact_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec request_observable_links(PlannedSourceRequest.t(), keyword()) :: [DataLink.t()]
  def request_observable_links(%PlannedSourceRequest{} = request, opts \\ []) do
    request.observables
    |> List.wrap()
    |> Enum.take(1)
    |> Enum.map(&telemetry_point_link(request, &1, opts))
    |> Enum.reject(&is_nil/1)
  end

  defp limit_event_links(%PlannedSourceRequest{} = request, events, opts) do
    Enum.map(events, fn event ->
      event
      |> attr(:limit_event_id)
      |> string_id()
      |> case do
        nil ->
          nil

        event_id ->
          data_link(
            :limit_event,
            Keyword.get(opts, :label, "Limit event"),
            event_id,
            request_context(request, attr(event, :point_id), opts),
            opts
          )
      end
    end)
  end

  defp limit_definition_links(%PlannedSourceRequest{} = request, events, opts) do
    Enum.map(events, fn event ->
      event
      |> attr(:limit_definition_id)
      |> string_id()
      |> case do
        nil ->
          nil

        definition_id ->
          data_link(
            :limit_definition,
            Keyword.get(opts, :definition_label, "Limit definition"),
            definition_id,
            request_context(request, attr(event, :point_id), opts),
            opts
          )
      end
    end)
  end

  defp operational_resource_row_links(%PlannedSourceRequest{} = request, row, opts) do
    [
      operational_resource_link(
        request,
        :transport,
        attr(row, :transport_id),
        Keyword.get(opts, :transport_label, "Transport"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :source_endpoint,
        attr(row, :source_endpoint_id),
        Keyword.get(opts, :source_endpoint_label, "Source endpoint"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :ground_station,
        attr(row, :ground_station_id),
        Keyword.get(opts, :ground_station_label, "Ground station"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :link,
        attr(row, :link_id),
        Keyword.get(opts, :link_label, "Link"),
        row,
        opts
      ),
      operational_resource_link(
        request,
        :contact,
        attr(row, :contact_id),
        Keyword.get(opts, :contact_label, "Contact"),
        row,
        opts
      )
    ]
  end

  defp operational_resource_link(%PlannedSourceRequest{} = request, target, id, label, row, opts) do
    case string_id(id) do
      nil ->
        nil

      target_id ->
        context =
          request
          |> request_context(attr(row, :observable_id), opts)
          |> maybe_put(:operational_resource, operational_resource_context(row))

        data_link(target, label, target_id, context, opts)
    end
  end

  defp operational_resource_context(row) do
    %{
      resource_id: attr(row, :resource_id),
      scope_kind: attr(row, :scope_kind),
      transport_id: attr(row, :transport_id),
      source_endpoint_id: attr(row, :source_endpoint_id),
      ground_station_id: attr(row, :ground_station_id),
      link_id: attr(row, :link_id),
      contact_id: attr(row, :contact_id),
      adapter_key: attr(row, :adapter_key)
    }
    |> drop_empty_values()
  end

  defp telemetry_sample_evidence_ref(sample) do
    cond do
      string_id(attr(sample, :evidence_id)) ->
        %EvidenceRef{
          kind: :raw_evidence,
          id: attr(sample, :evidence_id),
          observed_at: observed_at(sample),
          source: :telemetry,
          confidence: :direct
        }

      string_id(attr(sample, :sample_id)) ->
        %EvidenceRef{
          kind: :telemetry_sample,
          id: attr(sample, :sample_id),
          observed_at: observed_at(sample),
          source: :telemetry,
          confidence: :direct
        }

      true ->
        nil
    end
  end

  defp limit_event_evidence_ref(event) do
    case string_id(attr(event, :limit_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :limit_event,
          id: event_id,
          observed_at: observed_at(event),
          source: :limits,
          confidence: :direct
        }
    end
  end

  defp limit_definition_interval_evidence_refs_for(interval) do
    [
      limit_definition_interval_evidence_ref(interval),
      limit_definition_lifecycle_event_evidence_ref(interval),
      limit_definition_evidence_ref(interval)
    ]
  end

  defp limit_definition_interval_evidence_ref(interval) do
    case string_id(attr(interval, :interval_id)) ||
           interval_id(:limit_definition, attr(interval, :definition_activation_key)) do
      nil ->
        nil

      interval_id ->
        %EvidenceRef{
          kind: :limit_definition_interval,
          id: interval_id,
          observed_at: attr(interval, :observed_at) || attr(interval, :active_from),
          source: :limits,
          confidence: limit_definition_interval_confidence(interval)
        }
    end
  end

  defp limit_definition_lifecycle_event_evidence_ref(interval) do
    case string_id(attr(interval, :limit_definition_lifecycle_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :limit_definition_lifecycle_event,
          id: event_id,
          observed_at: attr(interval, :observed_at),
          source: :limits,
          confidence: limit_definition_interval_confidence(interval)
        }
    end
  end

  defp limit_definition_evidence_ref(interval) do
    case string_id(attr(interval, :limit_definition_id)) do
      nil ->
        nil

      definition_id ->
        %EvidenceRef{
          kind: :limit_definition,
          id: definition_id,
          observed_at: attr(interval, :observed_at) || attr(interval, :active_from),
          source: :limits,
          confidence: limit_definition_interval_confidence(interval)
        }
    end
  end

  defp mission_event_evidence_refs_for(event) do
    [
      mission_event_evidence_ref(event),
      mission_event_source_operational_event_evidence_ref(event)
    ]
  end

  defp mission_event_evidence_ref(event) do
    case string_id(attr(event, :mission_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :mission_event,
          id: event_id,
          observed_at: attr(event, :occurred_at),
          source: :events,
          confidence: :projected
        }
    end
  end

  defp mission_event_source_operational_event_evidence_ref(event) do
    if attr(event, :source_record_kind) in [:operational_event, "operational_event"] do
      case string_id(attr(event, :source_record_id)) do
        nil ->
          nil

        event_id ->
          %EvidenceRef{
            kind: :operational_event,
            id: event_id,
            observed_at: attr(event, :occurred_at),
            source: :events,
            confidence: :direct
          }
      end
    end
  end

  defp operational_event_evidence_ref(event, source) do
    case string_id(attr(event, :source_event_id) || attr(event, :event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_event,
          id: event_id,
          observed_at: attr(event, :observed_at) || attr(event, :occurred_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp source_health_event_evidence_refs_for(event) do
    [
      source_health_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :source_health_event,
        attr(event, :source_health_event_id),
        attr(event, :observed_at),
        attr(event, :replay_run_id)
      )
    ]
  end

  defp source_health_event_evidence_ref(event) do
    case string_id(attr(event, :source_health_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :source_health_event,
          id: event_id,
          observed_at: attr(event, :observed_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp source_watermark_event_evidence_ref(event) do
    case string_id(attr(event, :source_watermark_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :source_watermark_event,
          id: event_id,
          observed_at: attr(event, :observed_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp source_watermark_event_evidence_refs_for(event) do
    [
      source_watermark_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :source_watermark_event,
        attr(event, :source_watermark_event_id),
        attr(event, :observed_at),
        attr(event, :replay_run_id)
      )
    ]
  end

  defp source_capability_posture_event_evidence_ref(event) do
    case source_capability_posture_operational_event_id(event) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_event,
          id: event_id,
          observed_at: attr(event, :occurred_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp source_binding_interval_evidence_refs_for(interval, source) do
    [
      source_binding_interval_evidence_ref(interval, source),
      source_binding_event_evidence_ref(interval, source),
      source_binding_evidence_ref(interval, source)
    ]
  end

  defp source_binding_interval_evidence_ref(interval, source) do
    interval_id =
      string_id(attr(interval, :interval_id)) ||
        interval_id(:source_binding, attr(interval, :data_binding_event_id))

    case interval_id do
      nil ->
        nil

      interval_id ->
        %EvidenceRef{
          kind: :source_binding_interval,
          id: interval_id,
          observed_at: attr(interval, :started_at) || attr(interval, :active_from),
          source: normalize_source(source),
          confidence: :projected
        }
    end
  end

  defp source_binding_event_evidence_ref(interval, source) do
    case string_id(attr(interval, :data_binding_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :source_binding_event,
          id: event_id,
          observed_at: attr(interval, :started_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp source_binding_evidence_ref(interval, source) do
    case string_id(attr(interval, :binding_id)) do
      nil ->
        nil

      binding_id ->
        %EvidenceRef{
          kind: :source_binding,
          id: binding_id,
          observed_at: attr(interval, :started_at) || attr(interval, :active_from),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp telemetry_revision_decision_event_evidence_refs_for(event) do
    [
      telemetry_revision_decision_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :telemetry_observation_identity_decision_event,
        attr(event, :decision_event_id),
        attr(event, :occurred_at) || attr(event, :decided_at)
      )
    ]
  end

  defp telemetry_revision_decision_event_evidence_ref(event) do
    case string_id(attr(event, :decision_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :telemetry_revision_decision_event,
          id: event_id,
          observed_at: attr(event, :occurred_at) || attr(event, :decided_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp telemetry_backfill_lifecycle_event_evidence_refs_for(event) do
    [
      telemetry_backfill_lifecycle_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :telemetry_backfill_lifecycle_event,
        attr(event, :backfill_lifecycle_event_id),
        attr(event, :occurred_at)
      )
    ]
  end

  defp telemetry_backfill_lifecycle_event_evidence_ref(event) do
    case string_id(attr(event, :backfill_lifecycle_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :telemetry_backfill_lifecycle_event,
          id: event_id,
          observed_at: attr(event, :occurred_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp canonical_operational_event_evidence_ref(source_record_kind, source_record_id, observed_at) do
    canonical_operational_event_evidence_ref(
      source_record_kind,
      source_record_id,
      observed_at,
      nil
    )
  end

  defp canonical_operational_event_evidence_ref(
         source_record_kind,
         source_record_id,
         observed_at,
         replay_run_id
       ) do
    case canonical_operational_event_id(source_record_kind, source_record_id, replay_run_id) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_event,
          id: event_id,
          observed_at: observed_at,
          source: :events,
          confidence: :direct
        }
    end
  end

  defp contact_evidence_ref(contact) do
    case string_id(contact_id(contact)) do
      nil ->
        nil

      contact_id ->
        %EvidenceRef{
          kind: contact_kind(contact),
          id: contact_id,
          observed_at: attr(contact, :starts_at) || attr(contact, :realized_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp contact_kind(contact) do
    cond do
      attr(contact, :realized_contact_id) -> :realized_contact
      attr(contact, :scheduled_contact_id) -> :scheduled_contact
      true -> :contact
    end
  end

  defp contact_id(contact) do
    attr(contact, :realized_contact_id) || attr(contact, :scheduled_contact_id)
  end

  defp operational_event_subject_id(event) do
    [
      :subject_id,
      :contact_id,
      :scheduled_contact_id,
      :realized_contact_id,
      :transport_id,
      :source_endpoint_id,
      :ground_station_id,
      :link_id,
      :resource_id,
      :source_record_id
    ]
    |> Enum.find_value(&attr(event, &1))
  end

  defp operational_interval_evidence_refs_for(interval, source) do
    [
      operational_interval_evidence_ref(interval, source),
      operational_interval_source_event_evidence_ref(interval, source)
    ]
  end

  defp operational_interval_evidence_ref(interval, source) do
    case string_id(attr(interval, :interval_id)) do
      nil ->
        nil

      interval_id ->
        %EvidenceRef{
          kind: operational_interval_kind(interval),
          id: interval_id,
          observed_at: attr(interval, :starts_at),
          source: normalize_source(source),
          confidence: :projected
        }
    end
  end

  defp operational_interval_source_event_evidence_ref(interval, source) do
    case string_id(attr(interval, :source_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_interval,
          id: event_id,
          observed_at: attr(interval, :starts_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp operational_interval_kind(:binding_set), do: :binding_set_interval
  defp operational_interval_kind("binding_set"), do: :binding_set_interval
  defp operational_interval_kind(:application_binding), do: :application_binding_interval
  defp operational_interval_kind("application_binding"), do: :application_binding_interval
  defp operational_interval_kind(:catalog_revision), do: :catalog_revision_interval
  defp operational_interval_kind("catalog_revision"), do: :catalog_revision_interval
  defp operational_interval_kind(:source_binding), do: :source_binding_interval
  defp operational_interval_kind("source_binding"), do: :source_binding_interval
  defp operational_interval_kind(:transport_execution), do: :transport_execution_interval
  defp operational_interval_kind("transport_execution"), do: :transport_execution_interval

  defp operational_interval_kind(:transport_connection_state),
    do: :transport_connection_state_interval

  defp operational_interval_kind("transport_connection_state"),
    do: :transport_connection_state_interval

  defp operational_interval_kind(:ground_station_connection_state),
    do: :ground_station_connection_state_interval

  defp operational_interval_kind("ground_station_connection_state"),
    do: :ground_station_connection_state_interval

  defp operational_interval_kind(:link_rf_lock_state), do: :link_rf_lock_state_interval
  defp operational_interval_kind("link_rf_lock_state"), do: :link_rf_lock_state_interval

  defp operational_interval_kind(:link_frame_sync_state),
    do: :link_frame_sync_state_interval

  defp operational_interval_kind("link_frame_sync_state"),
    do: :link_frame_sync_state_interval

  defp operational_interval_kind(interval) when is_map(interval) do
    kind = attr(interval, :kind)
    payload = attr(interval, :payload) || %{}

    if kind in [:operational_observable_state, "operational_observable_state"] and
         attr(payload, :observable_id) == "ground.station.antenna_pointing_state" do
      :ground_station_antenna_pointing_state_interval
    else
      operational_interval_kind(kind)
    end
  end

  defp operational_interval_kind(_kind), do: :operational_interval

  defp event_link(nil, _target, _label, _context, _opts), do: nil

  defp event_link(event_id, target, default_label, context, opts) do
    data_link(
      target,
      Keyword.get(opts, :label, default_label),
      event_id,
      context,
      opts
    )
  end

  defp operational_event_link(
         %PlannedSourceRequest{} = request,
         source_record_kind,
         source_record_id,
         subject_id,
         opts,
         replay_run_id \\ nil
       ) do
    source_record_kind
    |> canonical_operational_event_id(source_record_id, replay_run_id)
    |> event_link(
      :operational_event,
      "Canonical operational event",
      request_context(request, subject_id, opts),
      opts
    )
  end

  defp canonical_operational_event_id(_source_record_kind, nil), do: nil

  defp canonical_operational_event_id(source_record_kind, source_record_id) do
    canonical_operational_event_id(source_record_kind, source_record_id, nil)
  end

  defp canonical_operational_event_id(_source_record_kind, nil, _replay_run_id), do: nil

  defp canonical_operational_event_id(source_record_kind, source_record_id, replay_run_id) do
    case {source_record_kind, string_id(source_record_id)} do
      {:source_capability_posture, "operational_event:" <> _rest = event_id} ->
        event_id

      {:source_capability_posture, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_capability_posture, event_id, replay_run_id)

      {:source_health_event, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_health_event, event_id, replay_run_id)

      {:source_watermark_event, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_watermark_event, event_id, replay_run_id)

      {:telemetry_backfill_lifecycle_event, event_id} when is_binary(event_id) ->
        "operational_event:telemetry_backfill_lifecycle_event:#{event_id}"

      {:telemetry_observation_identity_decision_event, event_id} when is_binary(event_id) ->
        "operational_event:telemetry_observation_identity_decision_event:#{event_id}"

      _other ->
        nil
    end
  end

  defp scoped_operational_event_id(source_record_kind, source_record_id, replay_run_id)
       when is_binary(replay_run_id) and replay_run_id != "" do
    "operational_event:#{source_record_kind}:#{replay_run_id}:#{source_record_id}"
  end

  defp scoped_operational_event_id(source_record_kind, source_record_id, _replay_run_id) do
    "operational_event:#{source_record_kind}:#{source_record_id}"
  end

  defp data_link(target, label, target_id, context, opts) do
    %DataLink{
      link_id: Keyword.get(opts, :link_id, link_id(target, target_id, context)),
      label: label,
      target: target,
      target_id: target_id,
      route: Keyword.get(opts, :route),
      context: context,
      presentation: Keyword.get(opts, :presentation, :side_panel),
      source: Keyword.get(opts, :source, :field)
    }
  end

  defp link_id(target, target_id, context) do
    [target, target_id, Map.get(context, :source_request_id)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(":", &to_string/1)
  end

  defp dedupe_links(links) do
    Enum.uniq_by(links, &{&1.target, &1.target_id, &1.source})
  end

  defp observed_at(item) do
    attr(item, :receipt_time) || attr(item, :generation_time) || attr(item, :observed_at)
  end

  defp context_map(nil), do: %{}

  defp context_map(%_struct{} = context) do
    context
    |> Map.from_struct()
    |> drop_empty_values()
  end

  defp context_map(context) when is_map(context), do: drop_empty_values(context)
  defp context_map(context), do: context

  defp inferred_replay_realm(%PlannedSourceRequest{
         data_context: data_context,
         time_context: time_context
       }) do
    cond do
      explicit_realm?(data_context) ->
        nil

      normalized_time_mode(attr(time_context, :mode)) == :replay_run ->
        :replay

      true ->
        nil
    end
  end

  defp explicit_realm?(data_context) when is_map(data_context) do
    Map.has_key?(data_context, :realm) or Map.has_key?(data_context, "realm")
  end

  defp explicit_realm?(_data_context), do: false

  defp normalized_time_mode(value) when is_atom(value), do: value

  defp normalized_time_mode(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> case do
      "replay_run" -> :replay_run
      other -> other
    end
  end

  defp normalized_time_mode(value), do: value

  defp drop_empty_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> empty_value?(value) end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp source_binding_id(%{binding: binding}), do: attr(binding, :binding_id)
  defp source_binding_id(source_binding), do: attr(source_binding, :binding_id)

  defp source_binding_data_source_id(%{data_source: data_source}),
    do: attr(data_source, :data_source_id)

  defp source_binding_data_source_id(source_binding), do: attr(source_binding, :data_source_id)

  defp source_binding_dataset(%{binding: binding}), do: attr(binding, :dataset)
  defp source_binding_dataset(source_binding), do: attr(source_binding, :dataset)

  defp empty_value?(nil), do: true
  defp empty_value?(%{} = map), do: map_size(map) == 0
  defp empty_value?([]), do: true
  defp empty_value?(_value), do: false

  defp source_capability_posture_operational_event_id(event) do
    attr(event, :event_id) ||
      canonical_operational_event_id(
        :source_capability_posture,
        event |> attr(:causality) |> attr(:source_record_id)
      )
  end

  defp source_capability_posture_subject_id(event) do
    event
    |> attr(:subject)
    |> attr(:id)
  end

  defp attr(item, key) when is_map(item) and is_atom(key) do
    Map.get(item, key, Map.get(item, Atom.to_string(key)))
  end

  defp attr(_item, _key), do: nil

  defp string_id(value) when is_binary(value) and value != "", do: value
  defp string_id(_value), do: nil

  defp interval_id(kind, event_id) do
    with event_id when is_binary(event_id) and event_id != "" <- string_id(event_id) do
      "effective_interval:#{kind}:#{event_id}"
    end
  end

  defp limit_definition_interval_confidence(interval) do
    case attr(interval, :complete?) do
      false -> :best_effort
      _other -> :direct
    end
  end

  defp normalize_source(source)
       when source in [:telemetry, :limits, :events, :operational_observables],
       do: source

  defp normalize_source(source) when is_binary(source) do
    source
    |> String.replace("-", "_")
    |> case do
      "telemetry" -> :telemetry
      "limits" -> :limits
      "events" -> :events
      "operational_observables" -> :operational_observables
      _other -> nil
    end
  end

  defp normalize_source(_source), do: nil
end
