defmodule Cadence.Dashboards.Sources.Events do
  @moduledoc """
  Dashboard events source adapter.

  v0 exposes operational context that already exists in Cadence:

  * contact intervals from scheduled and realized contacts
  * mission timeline annotations from the `mission_events` projection
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext,
    SourceCapabilities,
    SourceFacts,
    SourceResult
  }

  alias Cadence.Jobs

  import Cadence.Dashboards.Sources.Events.RequestPlanning
  import Cadence.Dashboards.Sources.Events.Reads

  @supported_products [
    :contact_intervals,
    :mission_timeline,
    :source_health_transitions,
    :source_watermark_events,
    :source_capability_postures,
    :telemetry_backfill_lifecycle,
    :telemetry_revision_decisions
  ]
  @supported_sampling [:event_history]

  @type scheduled_contacts_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type realized_contacts_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type contact_operational_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type mission_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type source_health_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type source_watermark_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type source_capability_posture_events_fun :: (binary() | nil, binary(), keyword() ->
                                                   [struct()])
  @type telemetry_backfill_lifecycle_events_fun :: (binary() | nil, binary(), keyword() ->
                                                      [struct()])
  @type telemetry_revision_decision_events_fun :: (binary() | nil, binary(), keyword() ->
                                                     [struct()])

  @spec capabilities() :: SourceCapabilities.t()
  def capabilities do
    SourceCapabilities.new(%{
      logical_source: :events,
      supported_sampling: @supported_sampling,
      supported_products: @supported_products,
      supported_time_axes: [:occurred_at],
      supported_value_types: [],
      supported_shapes: [:intervals, :events],
      supports_watermarks?: false,
      completeness: :partial,
      metadata: %{
        supported_families: [
          :contacts,
          :mission_timeline,
          :source_health,
          :source_watermarks,
          :source_capabilities,
          :telemetry_backfills,
          :telemetry_revisions
        ],
        unsupported_families: [
          :commands,
          :catalog_runtime,
          :replay,
          :eclipse,
          :flight_dynamics
        ]
      }
    })
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with :ok <- ensure_events_source(request),
         :ok <- ensure_supported_sampling(request),
         {:ok, _organization_id} <- required_request_context(request, :organization_id),
         {:ok, _mission_id} <- required_request_context(request, :mission_id) do
      {:ok,
       SourceFacts.new(%{
         source_binding: source_binding && source_binding.binding,
         data_source: source_binding && source_binding.data_source,
         source_health: Keyword.get(opts, :source_health, :healthy),
         meta: %{
           logical_source: :events,
           source_binding_id: source_binding_id(source_binding),
           data_source_id: data_source_id(request, source_binding)
         }
       })}
    else
      {:warning, warning} -> {:error, warning}
    end
  end

  @spec resolve(PlannedSourceRequest.t(), keyword()) :: SourceResult.t()
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with :ok <- ensure_events_source(request),
         :ok <- ensure_supported_sampling(request),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         {:ok, mission_id} <- required_request_context(request, :mission_id) do
      {products, product_warnings} = requested_products(request)
      time_warnings = time_axis_warnings(request)

      {frames, read_warnings} =
        resolve_frames(
          request,
          source_binding,
          organization_id,
          mission_id,
          products,
          opts,
          product_warnings ++ time_warnings
        )

      warnings = product_warnings ++ time_warnings ++ read_warnings

      SourceResult.new(%{
        request_id: request.request_id,
        frames: frames,
        warnings: warnings,
        watermarks: [],
        meta: %{
          logical_source: :events,
          source_binding_id: source_binding_id(source_binding),
          data_source_id: data_source_id(request, source_binding),
          supported_capability: products,
          returned_frame_count: length(frames),
          degraded?: degraded?(warnings)
        }
      })
    else
      {:warning, warning} ->
        SourceResult.new(%{
          request_id: request.request_id,
          warnings: [warning],
          meta: %{
            logical_source: request.logical_source,
            source_binding_id: source_binding_id(source_binding),
            data_source_id: data_source_id(request, source_binding),
            supported_capability: @supported_products,
            returned_frame_count: 0,
            degraded?: true
          }
        })
    end
  end

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         products,
         opts,
         _request_warnings
       ) do
    limit = request_limit(request)

    {contact_frames, contact_warnings} =
      if :contact_intervals in products do
        {[
           contact_interval_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {timeline_frames, timeline_warnings} =
      if :mission_timeline in products do
        {[
           mission_timeline_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {source_health_frames, source_health_warnings} =
      if :source_health_transitions in products do
        {[
           source_health_transition_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {source_watermark_frames, source_watermark_warnings} =
      if :source_watermark_events in products do
        {[
           source_watermark_event_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {source_capability_frames, source_capability_warnings} =
      if :source_capability_postures in products do
        {[
           source_capability_posture_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {telemetry_backfill_frames, telemetry_backfill_warnings} =
      if :telemetry_backfill_lifecycle in products do
        {[
           telemetry_backfill_lifecycle_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {telemetry_revision_frames, telemetry_revision_warnings} =
      if :telemetry_revision_decisions in products do
        {[
           telemetry_revision_decision_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             opts,
             limit
           )
         ], []}
      else
        {[], []}
      end

    {contact_frames ++
       timeline_frames ++
       source_health_frames ++
       source_watermark_frames ++
       source_capability_frames ++
       telemetry_backfill_frames ++
       telemetry_revision_frames,
     contact_warnings ++
       timeline_warnings ++
       source_health_warnings ++
       source_watermark_warnings ++
       source_capability_warnings ++
       telemetry_backfill_warnings ++
       telemetry_revision_warnings}
  end

  defp contact_interval_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    contact_opts = contact_opts(request, source_binding, limit)

    contacts =
      contact_intervals(request, organization_id, mission_id, contact_opts, opts)
      |> Enum.filter(fn interval ->
        interval_overlaps_request?(interval, request) and
          interval_matches_scope?(interval, request)
      end)
      |> Enum.sort_by(&interval_sort_key/1)
      |> Enum.take(limit)

    %Frame{
      frame_id: "#{request.request_id}:contact_intervals",
      source: :events,
      shape: :intervals,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "starts_at", kind: :time, values: Enum.map(contacts, & &1.starts_at)},
        %Field{name: "ends_at", kind: :time, values: Enum.map(contacts, & &1.ends_at)},
        %Field{name: "kind", kind: :enum, values: Enum.map(contacts, & &1.kind)},
        %Field{name: "status", kind: :enum, values: Enum.map(contacts, & &1.status)},
        %Field{name: "label", kind: :string, values: Enum.map(contacts, & &1.label)},
        %Field{name: "contact_id", kind: :string, values: Enum.map(contacts, & &1.contact_id)},
        %Field{
          name: "source_event_id",
          kind: :string,
          values: Enum.map(contacts, &contact_interval_source_event_id/1)
        }
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :contacts,
          product: :contact_intervals,
          projection: contact_interval_projection(request),
          returned_intervals: length(contacts),
          truncated?: length(contacts) == limit,
          evidence: contact_interval_evidence_refs(contacts),
          links:
            DataLinks.contact_links(request, Enum.map(contacts, & &1.source), source: :frame) ++
              DataLinks.operational_event_links(request, Enum.map(contacts, & &1.source),
                source: :frame
              ),
          warning_codes: []
        })
    }
  end

  defp contact_interval_source_event_id(interval) do
    interval
    |> get_attr(:source)
    |> get_attr(:source_event_id)
  end

  defp contact_intervals(
         %PlannedSourceRequest{} = request,
         organization_id,
         mission_id,
         opts,
         funs
       ) do
    if replay_run_id(request) do
      contact_events_fun =
        Keyword.get(funs, :contact_operational_events_fun, &default_contact_operational_events/3)

      contact_events_fun.(organization_id, mission_id, opts)
      |> Enum.map(&operational_contact_interval/1)
      |> Enum.reject(&is_nil/1)
    else
      scheduled_fun = Keyword.get(funs, :scheduled_contacts_fun, &default_scheduled_contacts/3)
      realized_fun = Keyword.get(funs, :realized_contacts_fun, &default_realized_contacts/3)

      scheduled_fun.(organization_id, mission_id, opts)
      |> Enum.map(&scheduled_contact_interval/1)
      |> Kernel.++(
        realized_fun.(organization_id, mission_id, opts)
        |> Enum.map(&realized_contact_interval/1)
      )
    end
  end

  defp mission_timeline_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    event_opts = mission_event_opts(request, source_binding, limit)
    mission_events_fun = Keyword.get(opts, :mission_events_fun, &default_mission_events/3)

    events =
      mission_events_fun.(organization_id, mission_id, event_opts)
      |> Enum.filter(&event_in_request_range?(&1, request))
      |> Enum.sort_by(&event_sort_key/1)
      |> Enum.take(limit)

    %Frame{
      frame_id: "#{request.request_id}:mission_timeline",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: Enum.map(events, & &1.occurred_at)},
        %Field{name: "category", kind: :enum, values: Enum.map(events, & &1.category)},
        %Field{name: "kind", kind: :enum, values: Enum.map(events, & &1.kind)},
        %Field{name: "severity", kind: :enum, values: Enum.map(events, & &1.severity)},
        %Field{name: "title", kind: :string, values: Enum.map(events, & &1.title)},
        %Field{
          name: "mission_event_id",
          kind: :string,
          values: Enum.map(events, & &1.mission_event_id)
        },
        %Field{
          name: "source_record_id",
          kind: :string,
          values: Enum.map(events, & &1.source_record_id)
        }
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :mission_timeline,
          product: :mission_timeline,
          projection: mission_timeline_projection(request),
          cursor: mission_event_cursor(events),
          returned_events: length(events),
          truncated?: length(events) == limit,
          evidence: DataLinks.mission_event_evidence_refs(events),
          links: DataLinks.mission_event_links(request, events, source: :frame),
          warning_codes: []
        })
    }
  end

  defp source_health_transition_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    source_health_opts = source_health_opts(request, limit)

    source_health_events_fun =
      Keyword.get(opts, :source_health_events_fun, &default_source_health_events/3)

    events =
      source_health_events_fun.(organization_id, mission_id, source_health_opts)
      |> Enum.sort_by(&event_sort_key/1)
      |> Enum.take(limit)

    %Frame{
      frame_id: "#{request.request_id}:source_health_transitions",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: Enum.map(events, & &1.observed_at)},
        %Field{name: "category", kind: :enum, values: repeat(:source_health, events)},
        %Field{name: "kind", kind: :enum, values: Enum.map(events, & &1.event_type)},
        %Field{
          name: "severity",
          kind: :enum,
          values: Enum.map(events, &source_health_severity/1)
        },
        %Field{name: "title", kind: :string, values: Enum.map(events, &source_health_title/1)},
        %Field{
          name: "source_record_id",
          kind: :string,
          values: Enum.map(events, & &1.source_health_event_id)
        },
        %Field{name: "source_health", kind: :enum, values: Enum.map(events, & &1.source_health)},
        %Field{
          name: "previous_source_health",
          kind: :enum,
          values: Enum.map(events, & &1.previous_source_health)
        },
        %Field{name: "reason", kind: :enum, values: Enum.map(events, & &1.reason)},
        %Field{
          name: "logical_source",
          kind: :enum,
          values: Enum.map(events, & &1.logical_source)
        },
        %Field{
          name: "data_source_id",
          kind: :string,
          values: Enum.map(events, & &1.data_source_id)
        },
        %Field{
          name: "source_binding_id",
          kind: :string,
          values: Enum.map(events, & &1.source_binding_id)
        },
        %Field{name: "realm", kind: :enum, values: Enum.map(events, & &1.realm)},
        %Field{
          name: "replay_run_id",
          kind: :string,
          values: Enum.map(events, & &1.replay_run_id)
        },
        %Field{
          name: "dataset",
          kind: :string,
          values: Enum.map(events, & &1.dataset)
        }
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :source_health,
          product: :source_health_transitions,
          projection: :dashboard_source_health_events,
          cursor: source_health_event_cursor(events),
          returned_events: length(events),
          truncated?: length(events) == limit,
          evidence: DataLinks.source_health_event_evidence_refs(events),
          links: DataLinks.source_health_event_links(request, events, source: :frame),
          warning_codes: []
        })
    }
  end

  defp source_watermark_event_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    source_watermark_opts = source_watermark_opts(request, limit)

    source_watermark_events_fun =
      Keyword.get(opts, :source_watermark_events_fun, &default_source_watermark_events/3)

    events =
      source_watermark_events_fun.(organization_id, mission_id, source_watermark_opts)
      |> Enum.sort_by(&event_sort_key/1)
      |> Enum.take(limit)

    %Frame{
      frame_id: "#{request.request_id}:source_watermark_events",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: Enum.map(events, & &1.observed_at)},
        %Field{name: "category", kind: :enum, values: repeat(:source_watermark, events)},
        %Field{name: "kind", kind: :enum, values: Enum.map(events, & &1.event_type)},
        %Field{
          name: "severity",
          kind: :enum,
          values: Enum.map(events, &source_watermark_severity/1)
        },
        %Field{name: "title", kind: :string, values: Enum.map(events, &source_watermark_title/1)},
        %Field{
          name: "source_record_id",
          kind: :string,
          values: Enum.map(events, & &1.source_watermark_event_id)
        },
        %Field{
          name: "logical_source",
          kind: :enum,
          values: Enum.map(events, & &1.logical_source)
        },
        %Field{
          name: "data_source_id",
          kind: :string,
          values: Enum.map(events, & &1.data_source_id)
        },
        %Field{
          name: "source_binding_id",
          kind: :string,
          values: Enum.map(events, & &1.source_binding_id)
        },
        %Field{name: "realm", kind: :enum, values: Enum.map(events, & &1.realm)},
        %Field{
          name: "replay_run_id",
          kind: :string,
          values: Enum.map(events, & &1.replay_run_id)
        },
        %Field{name: "dataset", kind: :string, values: Enum.map(events, & &1.dataset)},
        %Field{
          name: "complete_through",
          kind: :time,
          values: Enum.map(events, & &1.complete_through)
        },
        %Field{
          name: "previous_complete_through",
          kind: :time,
          values: Enum.map(events, & &1.previous_complete_through)
        },
        %Field{
          name: "latest_receipt_time",
          kind: :time,
          values: Enum.map(events, & &1.latest_receipt_time)
        },
        %Field{
          name: "previous_latest_receipt_time",
          kind: :time,
          values: Enum.map(events, & &1.previous_latest_receipt_time)
        },
        %Field{
          name: "retention_starts_at",
          kind: :time,
          values: Enum.map(events, & &1.retention_starts_at)
        },
        %Field{name: "confidence", kind: :enum, values: Enum.map(events, & &1.confidence)},
        %Field{name: "reason", kind: :enum, values: Enum.map(events, & &1.reason)}
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :source_watermark,
          product: :source_watermark_events,
          projection: :dashboard_source_watermark_events,
          cursor: source_watermark_event_cursor(events),
          returned_events: length(events),
          truncated?: length(events) == limit,
          evidence: DataLinks.source_watermark_event_evidence_refs(events),
          links: DataLinks.source_watermark_event_links(request, events, source: :frame),
          warning_codes: []
        })
    }
  end

  defp source_capability_posture_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    source_capability_opts = source_capability_posture_opts(request, limit)

    source_capability_posture_events_fun =
      Keyword.get(
        opts,
        :source_capability_posture_events_fun,
        &default_source_capability_posture_events/3
      )

    events =
      source_capability_posture_events_fun.(organization_id, mission_id, source_capability_opts)
      |> Enum.sort_by(&event_sort_key/1)
      |> Enum.take(limit)

    %Frame{
      frame_id: "#{request.request_id}:source_capability_postures",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "occurred_at",
          kind: :time,
          values: Enum.map(events, &get_attr(&1, :occurred_at))
        },
        %Field{name: "category", kind: :enum, values: repeat(:source_capability, events)},
        %Field{name: "kind", kind: :enum, values: Enum.map(events, &get_attr(&1, :kind))},
        %Field{name: "severity", kind: :enum, values: Enum.map(events, &get_attr(&1, :severity))},
        %Field{
          name: "title",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_title/1)
        },
        %Field{
          name: "source_record_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_record_id/1)
        },
        %Field{
          name: "operational_event_id",
          kind: :string,
          values: Enum.map(events, &get_attr(&1, :event_id))
        },
        %Field{
          name: "source_request_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :source_request_id))
        },
        %Field{
          name: "dashboard_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :dashboard_id))
        },
        %Field{
          name: "resolve_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :resolve_id))
        },
        %Field{
          name: "logical_source",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :logical_source))
        },
        %Field{
          name: "data_source_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :data_source_id))
        },
        %Field{
          name: "source_binding_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :source_binding_id))
        },
        %Field{
          name: "realm",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :realm))
        },
        %Field{
          name: "replay_run_id",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :replay_run_id))
        },
        %Field{
          name: "dataset",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_value(&1, :dataset))
        },
        %Field{
          name: "capability_status",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :status))
        },
        %Field{
          name: "requested_time_axis",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :requested_time_axis))
        },
        %Field{
          name: "executed_time_axis",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :executed_time_axis))
        },
        %Field{
          name: "supported_time_axes",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_text(&1, :supported_time_axes))
        },
        %Field{
          name: "requested_sampling",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :requested_sampling))
        },
        %Field{
          name: "supported_sampling",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_text(&1, :supported_sampling))
        },
        %Field{
          name: "requested_products",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_text(&1, :requested_products))
        },
        %Field{
          name: "supported_products",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_text(&1, :supported_products))
        },
        %Field{
          name: "fallbacks",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_text(&1, :fallbacks))
        },
        %Field{
          name: "unsupported",
          kind: :string,
          values: Enum.map(events, &source_capability_posture_text(&1, :unsupported))
        },
        %Field{
          name: "source_execution_status",
          kind: :enum,
          values: Enum.map(events, &source_capability_posture_value(&1, :source_execution_status))
        },
        %Field{
          name: "source_execution_cache_status",
          kind: :enum,
          values:
            Enum.map(events, &source_capability_posture_value(&1, :source_execution_cache_status))
        }
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :source_capability,
          product: :source_capability_postures,
          projection: :operational_events,
          cursor: source_capability_posture_event_cursor(events),
          returned_events: length(events),
          truncated?: length(events) == limit,
          evidence: DataLinks.source_capability_posture_event_evidence_refs(events),
          links: DataLinks.source_capability_posture_event_links(request, events, source: :frame),
          warning_codes: []
        })
    }
  end

  defp telemetry_backfill_lifecycle_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    telemetry_backfill_opts = telemetry_backfill_lifecycle_opts(request, source_binding, limit)

    telemetry_backfill_lifecycle_events_fun =
      Keyword.get(
        opts,
        :telemetry_backfill_lifecycle_events_fun,
        &default_telemetry_backfill_lifecycle_events/3
      )

    events =
      telemetry_backfill_lifecycle_events_fun.(
        organization_id,
        mission_id,
        telemetry_backfill_opts
      )
      |> Enum.sort_by(&event_sort_key/1)
      |> Enum.take(limit)

    workflow_job_fun =
      Keyword.get(
        opts,
        :telemetry_backfill_workflow_job_fun,
        &default_telemetry_backfill_workflow_job/1
      )

    workflow_jobs = Enum.map(events, &workflow_job_fun.(&1))

    %Frame{
      frame_id: "#{request.request_id}:telemetry_backfill_lifecycle",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: Enum.map(events, & &1.occurred_at)},
        %Field{name: "category", kind: :enum, values: repeat(:telemetry_backfill, events)},
        %Field{name: "kind", kind: :enum, values: Enum.map(events, & &1.event_type)},
        %Field{
          name: "severity",
          kind: :enum,
          values: Enum.map(events, &telemetry_backfill_lifecycle_severity/1)
        },
        %Field{
          name: "title",
          kind: :string,
          values: Enum.map(events, &telemetry_backfill_lifecycle_title/1)
        },
        %Field{
          name: "source_record_id",
          kind: :string,
          values: Enum.map(events, & &1.backfill_lifecycle_event_id)
        },
        %Field{
          name: "backfill_run_id",
          kind: :string,
          values: Enum.map(events, & &1.backfill_run_id)
        },
        %Field{
          name: "workflow_run_id",
          kind: :string,
          values: Enum.map(events, &telemetry_backfill_workflow_run_id/1)
        },
        %Field{
          name: "workflow_job_id",
          kind: :string,
          values: Enum.map(workflow_jobs, &workflow_job_value(&1, :job_id))
        },
        %Field{
          name: "workflow_job_status",
          kind: :enum,
          values: Enum.map(workflow_jobs, &workflow_job_value(&1, :status))
        },
        %Field{
          name: "workflow_job_failure",
          kind: :string,
          values: Enum.map(workflow_jobs, &workflow_job_value(&1, :failure_reason))
        },
        %Field{name: "realm", kind: :enum, values: Enum.map(events, & &1.realm)},
        %Field{
          name: "replay_run_id",
          kind: :string,
          values: Enum.map(events, & &1.replay_run_id)
        },
        %Field{
          name: "data_source_id",
          kind: :string,
          values: Enum.map(events, & &1.data_source_id)
        },
        %Field{
          name: "source_binding_id",
          kind: :string,
          values: Enum.map(events, & &1.binding_id)
        },
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(events, & &1.observable_id)
        },
        %Field{name: "point_id", kind: :string, values: Enum.map(events, & &1.point_id)},
        %Field{
          name: "spacecraft_id",
          kind: :string,
          values: Enum.map(events, & &1.spacecraft_id)
        },
        %Field{name: "source_from", kind: :time, values: Enum.map(events, & &1.source_from)},
        %Field{name: "source_to", kind: :time, values: Enum.map(events, & &1.source_to)},
        %Field{name: "receipt_from", kind: :time, values: Enum.map(events, & &1.receipt_from)},
        %Field{name: "receipt_to", kind: :time, values: Enum.map(events, & &1.receipt_to)},
        %Field{name: "sample_count", kind: :number, values: Enum.map(events, & &1.sample_count)},
        %Field{
          name: "selected_sample_count",
          kind: :number,
          values: Enum.map(events, &backfill_payload_value(&1, :selected_sample_count))
        },
        %Field{
          name: "projection_effect",
          kind: :enum,
          values: Enum.map(events, &backfill_payload_value(&1, :projection_effect))
        },
        %Field{
          name: "write_validity_state",
          kind: :enum,
          values: Enum.map(events, &backfill_payload_value(&1, :write_validity_state))
        },
        %Field{
          name: "record_current_values",
          kind: :boolean,
          values: Enum.map(events, &backfill_payload_value(&1, :record_current_values))
        },
        %Field{
          name: "refresh_latest_value",
          kind: :boolean,
          values: Enum.map(events, &backfill_payload_value(&1, :refresh_latest_value))
        },
        %Field{name: "authority", kind: :enum, values: Enum.map(events, & &1.authority)},
        %Field{name: "reason", kind: :enum, values: Enum.map(events, & &1.reason)},
        %Field{name: "actor_id", kind: :string, values: Enum.map(events, & &1.actor_id)},
        %Field{name: "actor_kind", kind: :enum, values: Enum.map(events, & &1.actor_kind)}
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :telemetry_backfill,
          product: :telemetry_backfill_lifecycle,
          projection: :telemetry_backfill_lifecycle_events,
          evidence: DataLinks.telemetry_backfill_lifecycle_event_evidence_refs(events),
          links:
            DataLinks.telemetry_backfill_lifecycle_event_links(request, events,
              source: :frame,
              source_binding: source_binding
            ),
          cursor: telemetry_backfill_lifecycle_event_cursor(events),
          returned_events: length(events),
          truncated?: length(events) == limit,
          warning_codes: []
        })
    }
  end

  defp telemetry_revision_decision_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         limit
       ) do
    telemetry_revision_opts = telemetry_revision_decision_opts(request, source_binding, limit)

    telemetry_revision_decision_events_fun =
      Keyword.get(
        opts,
        :telemetry_revision_decision_events_fun,
        &default_telemetry_revision_decision_events/3
      )

    events =
      telemetry_revision_decision_events_fun.(
        organization_id,
        mission_id,
        telemetry_revision_opts
      )
      |> Enum.sort_by(&event_sort_key/1)
      |> Enum.take(limit)

    %Frame{
      frame_id: "#{request.request_id}:telemetry_revision_decisions",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: Enum.map(events, & &1.occurred_at)},
        %Field{name: "category", kind: :enum, values: repeat(:telemetry_revision, events)},
        %Field{name: "kind", kind: :enum, values: Enum.map(events, & &1.decision)},
        %Field{
          name: "severity",
          kind: :enum,
          values: Enum.map(events, &telemetry_revision_decision_severity/1)
        },
        %Field{
          name: "title",
          kind: :string,
          values: Enum.map(events, &telemetry_revision_decision_title/1)
        },
        %Field{
          name: "source_record_id",
          kind: :string,
          values: Enum.map(events, & &1.decision_event_id)
        },
        %Field{
          name: "observation_identity_id",
          kind: :string,
          values: Enum.map(events, & &1.observation_identity_id)
        },
        %Field{name: "realm", kind: :enum, values: Enum.map(events, & &1.realm)},
        %Field{
          name: "replay_run_id",
          kind: :string,
          values: Enum.map(events, & &1.replay_run_id)
        },
        %Field{
          name: "data_source_id",
          kind: :string,
          values: Enum.map(events, & &1.data_source_id)
        },
        %Field{
          name: "source_binding_id",
          kind: :string,
          values: Enum.map(events, & &1.binding_id)
        },
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(events, & &1.observable_id)
        },
        %Field{name: "point_id", kind: :string, values: Enum.map(events, & &1.point_id)},
        %Field{
          name: "spacecraft_id",
          kind: :string,
          values: Enum.map(events, & &1.spacecraft_id)
        },
        %Field{
          name: "decision_reason",
          kind: :string,
          values: Enum.map(events, & &1.decision_reason)
        },
        %Field{name: "actor_id", kind: :string, values: Enum.map(events, & &1.actor_id)},
        %Field{name: "actor_kind", kind: :enum, values: Enum.map(events, & &1.actor_kind)},
        %Field{
          name: "previous_validity_state",
          kind: :enum,
          values: Enum.map(events, &state_value(&1.previous_state, :validity_state))
        },
        %Field{
          name: "new_validity_state",
          kind: :enum,
          values: Enum.map(events, &state_value(&1.new_state, :validity_state))
        },
        %Field{
          name: "previous_canonical_revision",
          kind: :number,
          values: Enum.map(events, &state_value(&1.previous_state, :canonical_revision))
        },
        %Field{
          name: "new_canonical_revision",
          kind: :number,
          values: Enum.map(events, &state_value(&1.new_state, :canonical_revision))
        }
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :telemetry_revision,
          product: :telemetry_revision_decisions,
          projection: :telemetry_observation_identity_decision_events,
          evidence: DataLinks.telemetry_revision_decision_event_evidence_refs(events),
          links:
            DataLinks.telemetry_revision_decision_event_links(request, events,
              source: :frame,
              source_binding: source_binding
            ),
          cursor: telemetry_revision_decision_event_cursor(events),
          returned_events: length(events),
          truncated?: length(events) == limit,
          warning_codes: []
        })
    }
  end

  defp scheduled_contact_interval(contact) do
    %{
      kind: :scheduled_contact,
      contact_id: contact.scheduled_contact_id,
      starts_at: contact.starts_at,
      ends_at: contact.ends_at,
      status: contact.lifecycle_state,
      label: contact_label(:scheduled_contact, contact.scheduled_contact_id, contact),
      source_endpoint_refs: contact.source_endpoint_refs,
      source: contact
    }
  end

  defp operational_contact_interval(event) do
    contact_kind = operational_contact_kind(event)
    contact_id = operational_contact_id(event, contact_kind)
    starts_at = operational_contact_starts_at(event)

    if contact_id && contact_kind && starts_at do
      source =
        event
        |> operational_contact_source(contact_kind, contact_id, starts_at)
        |> compact_map()

      %{
        kind: contact_kind,
        contact_id: contact_id,
        starts_at: starts_at,
        ends_at: operational_contact_ends_at(event),
        status: operational_contact_status(event),
        label: operational_contact_label(event, contact_kind, contact_id),
        source_endpoint_refs: operational_contact_source_endpoint_refs(event),
        source: source
      }
    end
  end

  defp operational_contact_kind(event) do
    raw_kind =
      operational_contact_value(event, :contact_kind) ||
        operational_contact_value(event, :contact_type) ||
        get_attr(event, :kind)

    cond do
      scheduled_contact_kind?(raw_kind) -> :scheduled_contact
      realized_contact_kind?(raw_kind) -> :realized_contact
      true -> operational_contact_kind_from_ids(event)
    end
  end

  defp scheduled_contact_kind?(kind)
       when kind in [
              :scheduled_contact,
              "scheduled_contact",
              :scheduled_contact_interval,
              "scheduled_contact_interval",
              :contact_scheduled,
              "contact_scheduled"
            ],
       do: true

  defp scheduled_contact_kind?(_kind), do: false

  defp realized_contact_kind?(kind)
       when kind in [
              :realized_contact,
              "realized_contact",
              :realized_contact_interval,
              "realized_contact_interval",
              :contact_realized,
              "contact_realized",
              :contact_started,
              "contact_started"
            ],
       do: true

  defp realized_contact_kind?(_kind), do: false

  defp operational_contact_kind_from_ids(event) do
    cond do
      operational_contact_value(event, :realized_contact_id) -> :realized_contact
      operational_contact_value(event, :scheduled_contact_id) -> :scheduled_contact
      true -> nil
    end
  end

  defp operational_contact_id(event, :scheduled_contact) do
    operational_contact_value(event, :scheduled_contact_id) ||
      operational_contact_value(event, :contact_id) ||
      operational_contact_subject_id(event) ||
      operational_contact_source_record_id(event)
  end

  defp operational_contact_id(event, :realized_contact) do
    operational_contact_value(event, :realized_contact_id) ||
      operational_contact_value(event, :contact_id) ||
      operational_contact_subject_id(event) ||
      operational_contact_source_record_id(event)
  end

  defp operational_contact_id(_event, _kind), do: nil

  defp operational_contact_subject_id(event) do
    event
    |> get_attr(:subject)
    |> get_attr(:id)
  end

  defp operational_contact_source_record_id(event) do
    event
    |> get_attr(:causality)
    |> get_attr(:source_record_id)
  end

  defp operational_contact_starts_at(event) do
    event
    |> operational_contact_value(:starts_at)
    |> fallback(operational_contact_value(event, :start_at))
    |> fallback(operational_contact_value(event, :realized_at))
    |> fallback(get_attr(event, :effective_at))
    |> fallback(get_attr(event, :occurred_at))
    |> normalize_datetime()
  end

  defp operational_contact_ends_at(event) do
    event
    |> operational_contact_value(:ends_at)
    |> fallback(operational_contact_value(event, :end_at))
    |> fallback(operational_contact_value(event, :completed_at))
    |> fallback(operational_contact_value(event, :stopped_at))
    |> normalize_datetime()
  end

  defp operational_contact_status(event) do
    operational_contact_value(event, :status) ||
      operational_contact_value(event, :lifecycle_state) ||
      operational_contact_value(event, :state)
  end

  defp operational_contact_label(event, contact_kind, contact_id) do
    operational_contact_value(event, :label) ||
      operational_contact_value(event, :provider_contact_ref) ||
      contact_label(contact_kind, contact_id, %{provider_contact_ref: nil})
  end

  defp operational_contact_source_endpoint_refs(event) do
    event
    |> operational_contact_value(:source_endpoint_refs)
    |> fallback(operational_contact_value(event, :source_endpoint_ref))
    |> normalize_string_list()
  end

  defp operational_contact_source(event, :scheduled_contact, contact_id, starts_at) do
    %{
      kind: :scheduled_contact,
      interval_id: operational_contact_interval_id(event, contact_id),
      source_event_id: get_attr(event, :event_id),
      scheduled_contact_id: contact_id,
      starts_at: starts_at,
      ends_at: operational_contact_ends_at(event),
      lifecycle_state: operational_contact_status(event),
      provider_contact_ref: operational_contact_value(event, :provider_contact_ref),
      source_endpoint_refs: operational_contact_source_endpoint_refs(event)
    }
  end

  defp operational_contact_source(event, :realized_contact, contact_id, starts_at) do
    %{
      kind: :realized_contact,
      interval_id: operational_contact_interval_id(event, contact_id),
      source_event_id: get_attr(event, :event_id),
      realized_contact_id: contact_id,
      realized_at: starts_at,
      starts_at: starts_at,
      ends_at: operational_contact_ends_at(event),
      lifecycle_state: operational_contact_status(event),
      provider_contact_ref: operational_contact_value(event, :provider_contact_ref),
      source_endpoint_refs: operational_contact_source_endpoint_refs(event)
    }
  end

  defp operational_contact_interval_id(event, contact_id) do
    with event_id when is_binary(event_id) and event_id != "" <- get_attr(event, :event_id),
         contact_id when is_binary(contact_id) and contact_id != "" <- contact_id do
      "effective_interval:contact:#{event_id}:#{contact_id}"
    else
      _other -> nil
    end
  end

  defp operational_contact_value(event, key) do
    get_attr(get_attr(event, :current), key) ||
      get_attr(get_attr(event, :payload), key) ||
      get_attr(get_attr(event, :scope), key)
  end

  defp realized_contact_interval(contact) do
    starts_at = contact.realized_at || contact.initial_time

    %{
      kind: :realized_contact,
      contact_id: contact.realized_contact_id,
      starts_at: starts_at,
      ends_at: contact_end_time(contact.metadata),
      status: contact.lifecycle_state,
      label: contact_label(:realized_contact, contact.realized_contact_id, contact),
      source_endpoint_refs: contact.source_endpoint_refs,
      source: contact
    }
  end

  defp contact_label(kind, contact_id, contact) do
    case get_attr(contact, :provider_contact_ref) do
      ref when is_binary(ref) and ref != "" -> ref
      _other -> "#{kind |> Atom.to_string() |> String.replace("_", " ")} #{contact_id}"
    end
  end

  defp contact_interval_evidence_refs(contacts) do
    sources = Enum.map(contacts, & &1.source)

    sources
    |> DataLinks.contact_evidence_refs()
    |> Kernel.++(DataLinks.operational_interval_evidence_refs(sources, source: :events))
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  defp contact_end_time(metadata) when is_map(metadata) do
    metadata
    |> get_attr(:completed_at)
    |> fallback(get_attr(metadata, :stopped_at))
    |> fallback(get_attr(metadata, :ended_at))
    |> normalize_datetime()
  end

  defp contact_end_time(_metadata), do: nil

  defp interval_matches_scope?(interval, %PlannedSourceRequest{} = request) do
    if ScopeContext.primary_kind(request.scope_context) in [:source_endpoint, "source_endpoint"] do
      ids = ScopeContext.primary_ids(request.scope_context)

      ids == [] or
        not MapSet.disjoint?(MapSet.new(interval.source_endpoint_refs), MapSet.new(ids))
    else
      true
    end
  end

  defp interval_overlaps_request?(%{starts_at: nil}, %PlannedSourceRequest{}), do: false

  defp interval_overlaps_request?(interval, %PlannedSourceRequest{} = request) do
    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        DateTime.compare(interval.starts_at, to) == :lt and
          interval_ends_after?(interval.ends_at, from)

      _window ->
        true
    end
  end

  defp interval_ends_after?(nil, %DateTime{}), do: true

  defp interval_ends_after?(%DateTime{} = ends_at, %DateTime{} = from) do
    DateTime.compare(ends_at, from) == :gt
  end

  defp event_in_request_range?(event, %PlannedSourceRequest{} = request) do
    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        DateTime.compare(event.occurred_at, from) != :lt and
          DateTime.compare(event.occurred_at, to) == :lt

      _window ->
        true
    end
  end

  defp source_health_severity(%{source_health: :healthy}), do: :info
  defp source_health_severity(%{source_health: :degraded}), do: :warning
  defp source_health_severity(%{source_health: :unavailable}), do: :error
  defp source_health_severity(%{source_health: :unknown}), do: :warning
  defp source_health_severity(_event), do: :warning

  defp source_health_title(event) do
    [
      event.logical_source |> stringify() |> String.replace("_", " "),
      "source",
      event.source_health |> stringify() |> String.replace("_", " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp source_watermark_severity(%{event_type: :retreated}), do: :warning
  defp source_watermark_severity(%{event_type: :changed}), do: :info
  defp source_watermark_severity(%{event_type: :advanced}), do: :info
  defp source_watermark_severity(%{event_type: :observed}), do: :info
  defp source_watermark_severity(_event), do: :warning

  defp source_watermark_title(event) do
    [
      event.logical_source |> stringify() |> String.replace("_", " "),
      "watermark",
      event.event_type |> stringify() |> String.replace("_", " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp telemetry_backfill_lifecycle_severity(%{event_type: :backfill_failed}), do: :error
  defp telemetry_backfill_lifecycle_severity(%{event_type: :import_failed}), do: :error
  defp telemetry_backfill_lifecycle_severity(%{event_type: :backfill_rejected}), do: :warning
  defp telemetry_backfill_lifecycle_severity(%{event_type: :import_rejected}), do: :warning
  defp telemetry_backfill_lifecycle_severity(%{event_type: :late_data_rejected}), do: :warning
  defp telemetry_backfill_lifecycle_severity(_event), do: :info

  defp telemetry_backfill_lifecycle_title(event) do
    [
      event.observable_id || event.point_id,
      event.event_type |> stringify() |> String.replace("_", " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp default_telemetry_backfill_workflow_job(event) do
    with run_id when is_binary(run_id) and run_id != "" <-
           telemetry_backfill_workflow_run_id(event),
         {:ok, %Jobs.Job{} = job} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
      job
    else
      _other -> nil
    end
  end

  defp telemetry_backfill_workflow_run_id(event) do
    backfill_payload_value(event, :run_id) || event.backfill_run_id
  end

  defp workflow_job_value(%Jobs.Job{} = job, key), do: Map.get(job, key)
  defp workflow_job_value(_job, _key), do: nil

  defp telemetry_revision_decision_severity(%{decision: :mark_conflict}), do: :warning
  defp telemetry_revision_decision_severity(%{decision: :mark_superseded}), do: :warning
  defp telemetry_revision_decision_severity(%{decision: :mark_advisory}), do: :info
  defp telemetry_revision_decision_severity(%{decision: :mark_canonical}), do: :info
  defp telemetry_revision_decision_severity(_event), do: :info

  defp telemetry_revision_decision_title(event) do
    [
      event.observable_id || event.point_id,
      "revision",
      telemetry_revision_decision_label(event.decision)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp telemetry_revision_decision_label(nil), do: nil

  defp telemetry_revision_decision_label(decision) do
    decision
    |> stringify()
    |> String.replace("mark_", "")
    |> String.replace("_", " ")
  end

  defp source_capability_posture_title(event) do
    [
      source_capability_posture_label(source_capability_posture_value(event, :logical_source)),
      "capability",
      source_capability_posture_label(source_capability_posture_value(event, :status))
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp source_capability_posture_text(event, key) do
    case source_capability_posture_value(event, key) do
      nil -> nil
      [] -> nil
      values when is_list(values) -> Enum.map_join(values, ", ", &stringify/1)
      value -> stringify(value)
    end
  end

  defp source_capability_posture_label(nil), do: nil

  defp source_capability_posture_label(value) do
    value
    |> stringify()
    |> String.replace("_", " ")
  end

  defp backfill_payload_value(%{payload: payload}, key) when is_map(payload) and is_atom(key) do
    Map.get(payload, key, Map.get(payload, Atom.to_string(key)))
  end

  defp backfill_payload_value(_event, _key), do: nil

  defp state_value(state, key) when is_map(state), do: get_attr(state, key)
  defp state_value(_state, _key), do: nil

  defp repeat(value, values), do: Enum.map(values, fn _value -> value end)

  defp fallback(nil, value), do: value
  defp fallback(value, _fallback), do: value

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_string_list(nil), do: []
  defp normalize_string_list(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_string_list(value) when is_binary(value), do: [value]
  defp normalize_string_list(_value), do: []

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp degraded?(warnings) do
    Enum.any?(warnings, &(&1.severity != :info))
  end

  defp get_attr(nil, _key), do: nil

  defp get_attr(%_struct{} = struct, key) when is_atom(key) do
    struct
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp get_attr(_value, _key), do: nil

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: inspect(value)
end
