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
    SourceFacts,
    SourceResult
  }

  alias Cadence.DataSources.SourceCapabilities

  import Cadence.Dashboards.Sources.Events.RequestPlanning, except: [capabilities: 0]
  import Cadence.Dashboards.Sources.Events.Reads
  import Cadence.Dashboards.Sources.Events.ContactIntervals
  import Cadence.Dashboards.Sources.Events.Presentation

  @spec capabilities() :: SourceCapabilities.t()
  defdelegate capabilities(), to: Cadence.Dashboards.Sources.Events.RequestPlanning

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
            supported_capability: capabilities().supported_products,
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
          projection: :data_source_health_events,
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
          projection: :data_source_watermark_events,
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
end
