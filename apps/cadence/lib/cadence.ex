defmodule Cadence do
  @moduledoc """
  Core entry points for the redesigned Cadence system.

  The first implemented vertical slice is:

  1. raw ingress evidence
  2. canonical packet record decode
  3. governed application dispatch
  4. definition-bound telemetry handling
  5. canonical telemetry samples
  """

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.ApplicationDispatch.DispatchDecision
  alias Cadence.ApplicationDispatch.Dispatcher
  alias Cadence.Dashboards
  alias Cadence.Dashboards.DataSources, as: DashboardDataSources
  alias Cadence.DerivedTelemetry, as: DerivedTelemetryService
  alias Cadence.Governance
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Jobs
  alias Cadence.Limits, as: LimitsService
  alias Cadence.Missions
  alias Cadence.Ops.PointCatalog, as: OpsPointCatalog
  alias Cadence.Persistence
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints

  alias Cadence.Projections.DerivedTelemetryLatestValues,
    as: DerivedTelemetryLatestValueProjection

  alias Cadence.Projections.TelemetryLatestLimitStates, as: TelemetryLatestLimitStateProjection
  alias Cadence.Projections.TelemetryLatestValues, as: TelemetryLatestValueProjection
  alias Cadence.Protocol.{PacketRecord, ProtocolAnomaly, TMFrameIngress, TransferFrameRecord}
  alias Cadence.Protocol.SpacePacketDecoder
  alias Cadence.Reads.Replay, as: ReplayReads
  alias Cadence.Replay
  alias Cadence.Replay.Diff, as: ReplayDiff
  alias Cadence.Replay.Scope
  alias Cadence.Telemetry.DataManagement, as: TelemetryDataManagement
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler
  alias Cadence.Telemetry.RuntimeHealth
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  @type ingress_latency_metric :: %{
          value_ms: number(),
          end_to_end_us: non_neg_integer(),
          observed_at: DateTime.t(),
          error?: boolean()
        }

  @type processing_result :: %{
          raw_evidence: RawEvidence.t(),
          packet_records: [PacketRecord.t()],
          transfer_frame_records: [TransferFrameRecord.t()],
          protocol_anomalies: [ProtocolAnomaly.t()],
          dispatch_decisions: [DispatchDecision.t()],
          outputs: [term()],
          runtime_records: map(),
          ingress_latency_metric: ingress_latency_metric() | nil
        }

  @spec list_ops_telemetry_points(binary(), binary()) :: [OpsPointCatalog.point_info()]
  def list_ops_telemetry_points(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    OpsPointCatalog.list_points(organization_id, mission_id)
  end

  @spec list_dashboard_data_realms(binary(), binary()) :: [binary()]
  def list_dashboard_data_realms(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    DashboardDataSources.list_data_realms(organization_id, mission_id)
  end

  @spec process_telemetry_ingress(RawEvidence.t(), BindingSet.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence, %BindingSet{} = binding_set) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <- resolve_raw_evidence(raw_evidence),
         :ok <- validate_binding_set_mission(resolved_raw_evidence, binding_set),
         {:ok, decode_result} <- decode_raw_evidence_packets(resolved_raw_evidence),
         {:ok, dispatch_result} <- execute_dispatches(decode_result, binding_set) do
      {:ok, build_processing_result(resolved_raw_evidence, dispatch_result)}
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t(), binary()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence, binding_set_id)
      when is_binary(binding_set_id) do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_latest_binding_set(raw_evidence.mission_id, binding_set_id) do
      process_telemetry_ingress(raw_evidence, binding_set)
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t(), binary(), pos_integer()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence, binding_set_id, version)
      when is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(raw_evidence.mission_id, binding_set_id, version) do
      process_telemetry_ingress(raw_evidence, binding_set)
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <- resolve_raw_evidence(raw_evidence) do
      Runtime.process_telemetry_ingress(resolved_raw_evidence)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t(), BindingSet.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(
        %RawEvidence{} = raw_evidence,
        %BindingSet{} = binding_set
      ) do
    with {:ok, processing_result} <- process_telemetry_ingress(raw_evidence, binding_set) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t(), binary()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(%RawEvidence{} = raw_evidence, binding_set_id)
      when is_binary(binding_set_id) do
    with {:ok, processing_result} <- process_telemetry_ingress(raw_evidence, binding_set_id) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t(), binary(), pos_integer()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(
        %RawEvidence{} = raw_evidence,
        binding_set_id,
        version
      )
      when is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with {:ok, processing_result} <-
           process_telemetry_ingress(raw_evidence, binding_set_id, version) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist_telemetry_ingress(RawEvidence.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist_telemetry_ingress(%RawEvidence{} = raw_evidence) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      ingress_started_at = System.monotonic_time()

      resolve_result =
        TelemetryProfiler.with_stage(:resolve, fn ->
          resolve_raw_evidence(raw_evidence)
        end)

      resolve_us = elapsed_us(ingress_started_at)

      case resolve_result do
        {:ok, %RawEvidence{} = resolved_raw_evidence} ->
          handle_resolved_ingress(resolved_raw_evidence, ingress_started_at, resolve_us)

        {:error, reason} ->
          TelemetryProfiler.record_ingress_result(
            raw_evidence,
            resolve_us: resolve_us,
            end_to_end_us: elapsed_us(ingress_started_at),
            error?: true
          )

          {:error, reason}
      end
    end)
  end

  defp handle_resolved_ingress(
         %RawEvidence{} = resolved_raw_evidence,
         ingress_started_at,
         resolve_us
       ) do
    runtime_started_at = System.monotonic_time()

    runtime_result =
      TelemetryProfiler.with_stage(:runtime, fn ->
        Runtime.process_telemetry_ingress(resolved_raw_evidence)
      end)

    runtime_us = elapsed_us(runtime_started_at)

    case runtime_result do
      {:ok, processing_result} ->
        processing_result =
          put_ingress_latency_metric(
            processing_result,
            elapsed_us(ingress_started_at),
            false
          )

        finalize_persisted_ingress(
          resolved_raw_evidence,
          processing_result,
          ingress_started_at,
          resolve_us,
          runtime_us
        )

      {:error, reason} ->
        TelemetryProfiler.record_ingress_result(
          resolved_raw_evidence,
          resolve_us: resolve_us,
          runtime_us: runtime_us,
          end_to_end_us: elapsed_us(ingress_started_at),
          error?: true
        )

        {:error, reason}
    end
  end

  defp finalize_persisted_ingress(
         %RawEvidence{} = resolved_raw_evidence,
         processing_result,
         ingress_started_at,
         resolve_us,
         runtime_us
       ) do
    persistence_started_at = System.monotonic_time()

    persistence_result =
      TelemetryProfiler.with_stage(:persistence, fn ->
        Persistence.persist_processing_result(processing_result)
      end)

    persistence_us = elapsed_us(persistence_started_at)
    end_to_end_us = elapsed_us(ingress_started_at)

    TelemetryProfiler.record_ingress_result(
      resolved_raw_evidence,
      resolve_us: resolve_us,
      runtime_us: runtime_us,
      persistence_us: persistence_us,
      end_to_end_us: end_to_end_us,
      error?: match?({:error, _reason}, persistence_result),
      processing_result: processing_result
    )

    normalize_persistence_result(persistence_result)
  end

  defp normalize_persistence_result({:ok, persisted_result}), do: {:ok, persisted_result}
  defp normalize_persistence_result({:error, reason}), do: {:error, reason}

  defp put_ingress_latency_metric(processing_result, end_to_end_us, error?)
       when is_map(processing_result) and is_integer(end_to_end_us) and end_to_end_us >= 0 do
    raw_evidence = Map.get(processing_result, :raw_evidence)

    Map.put(processing_result, :ingress_latency_metric, %{
      value_ms: end_to_end_us / 1000.0,
      end_to_end_us: end_to_end_us,
      observed_at: ingress_latency_observed_at(raw_evidence),
      error?: error?
    })
  end

  defp ingress_latency_observed_at(%RawEvidence{receipt_time: %DateTime{} = receipt_time}),
    do: receipt_time

  defp ingress_latency_observed_at(_raw_evidence), do: DateTime.utc_now()

  @spec rebuild_mission_events(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_mission_events(mission_id) when is_binary(mission_id) do
    MissionEventProjection.rebuild(mission_id)
  end

  @spec rebuild_mission_events(binary(), binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_mission_events(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      MissionEventProjection.rebuild(mission_id)
    end
  end

  @spec start_rebuild_mission_events(binary()) ::
          {:ok, Cadence.Projections.MissionEvents.Run.t()} | {:error, term()}
  def start_rebuild_mission_events(mission_id) when is_binary(mission_id) do
    MissionEventProjection.start_rebuild(mission_id)
  end

  @spec start_rebuild_mission_events(binary(), binary()) ::
          {:ok, Cadence.Projections.MissionEvents.Run.t()} | {:error, term()}
  def start_rebuild_mission_events(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      MissionEventProjection.start_rebuild(mission_id)
    end
  end

  @spec fetch_mission_event_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.MissionEvents.Run.t()} | {:error, term()}
  def fetch_mission_event_rebuild_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    MissionEventProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_mission_event_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_mission_event_rebuild_job(rebuild_run_id) when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:mission_event_rebuild, rebuild_run_id)
  end

  @spec realized_contact_snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    Runtime.realized_contact_snapshot(mission_id, realized_contact_id)
  end

  @spec realized_contact_snapshot(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.realized_contact_snapshot(mission_id, realized_contact_id)
    end
  end

  @spec path_runtime_snapshot(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def path_runtime_snapshot(mission_id, realized_contact_id, path_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) do
    Runtime.path_runtime_snapshot(mission_id, realized_contact_id, path_id)
  end

  @spec path_runtime_snapshot(binary(), binary(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def path_runtime_snapshot(organization_id, mission_id, realized_contact_id, path_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_binary(path_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.path_runtime_snapshot(mission_id, realized_contact_id, path_id)
    end
  end

  @spec handle_path_transport_event(binary(), binary(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    Runtime.handle_path_transport_event(
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      event,
      opts
    )
  end

  @spec handle_path_transport_event(
          binary(),
          binary(),
          binary(),
          binary(),
          binary(),
          term(),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        organization_id,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.handle_path_transport_event(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts
      )
    end
  end

  @spec handle_path_control_input(binary(), binary(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    Runtime.handle_path_control_input(
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      control_input,
      opts
    )
  end

  @spec handle_path_control_input(
          binary(),
          binary(),
          binary(),
          binary(),
          binary(),
          term(),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        organization_id,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.handle_path_control_input(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
    end
  end

  @spec advance_realized_contact_time(binary(), binary(), DateTime.t()) :: :ok | {:error, term()}
  def advance_realized_contact_time(mission_id, realized_contact_id, %DateTime{} = target_time)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    Runtime.advance_realized_contact_time(mission_id, realized_contact_id, target_time)
  end

  @spec advance_realized_contact_time(binary(), binary(), binary(), DateTime.t()) ::
          :ok | {:error, term()}
  def advance_realized_contact_time(
        organization_id,
        mission_id,
        realized_contact_id,
        %DateTime{} = target_time
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      Runtime.advance_realized_contact_time(mission_id, realized_contact_id, target_time)
    end
  end

  defp resolve_raw_evidence(%RawEvidence{} = raw_evidence) do
    SourceEndpoints.resolve_raw_evidence(raw_evidence)
  end

  defp elapsed_us(started_at) when is_integer(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
  end

  @spec backfill_telemetry_samples([Cadence.Telemetry.Sample.t()], map(), keyword()) ::
          :ok | {:error, term()}
  def backfill_telemetry_samples(samples, attrs, opts \\ [])
      when is_list(samples) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.backfill_samples(samples, attrs, opts)
  end

  @spec import_telemetry_samples([Cadence.Telemetry.Sample.t()], map(), keyword()) ::
          :ok | {:error, term()}
  def import_telemetry_samples(samples, attrs, opts \\ [])
      when is_list(samples) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.import_samples(samples, attrs, opts)
  end

  @spec list_telemetry_backfill_lifecycle_events(binary(), keyword()) :: [
          Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()
        ]
  def list_telemetry_backfill_lifecycle_events(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryStorage.list_backfill_lifecycle_events(mission_id, opts)
  end

  @spec fetch_telemetry_backfill_lifecycle_event(binary(), keyword()) ::
          Cadence.Telemetry.Storage.BackfillLifecycleEvent.t() | nil
  def fetch_telemetry_backfill_lifecycle_event(backfill_lifecycle_event_id, opts \\ [])
      when is_binary(backfill_lifecycle_event_id) and is_list(opts) do
    TelemetryStorage.fetch_backfill_lifecycle_event(backfill_lifecycle_event_id, opts)
  end

  @spec record_telemetry_historical_data_workflow_event(
          atom() | binary(),
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_event(workflow, stage, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_event(workflow, stage, attrs, opts)
  end

  @spec record_telemetry_historical_data_workflow_request(
          atom() | binary(),
          map(),
          [binary() | nil],
          keyword()
        ) ::
          {:ok, [Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()]} | {:error, term()}
  def record_telemetry_historical_data_workflow_request(workflow, attrs, point_ids, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(point_ids) and
             is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_request(
      workflow,
      attrs,
      point_ids,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_correction_request(
          atom() | binary(),
          map(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_correction_request(
        workflow,
        attrs,
        correction,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_map(correction) and
             is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_correction_request(
      workflow,
      attrs,
      correction,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_correction_transition(
          atom() | binary(),
          atom() | binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_correction_transition(
        workflow,
        stage,
        correction_event_id,
        attrs,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(correction_event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_correction_transition(
      workflow,
      stage,
      correction_event_id,
      attrs,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_stage_transition(
          atom() | binary(),
          atom() | binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_stage_transition(
        workflow,
        stage,
        source_event_id,
        attrs,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(source_event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_stage_transition(
      workflow,
      stage,
      source_event_id,
      attrs,
      opts
    )
  end

  @spec telemetry_historical_data_workflow_action_policy(map()) :: %{
          retry_job: TelemetryDataManagement.historical_data_workflow_action_decision(),
          retry_group_failed_jobs:
            TelemetryDataManagement.historical_data_workflow_action_decision(),
          correction_request: TelemetryDataManagement.historical_data_workflow_action_decision()
        }
  def telemetry_historical_data_workflow_action_policy(context) when is_map(context) do
    TelemetryDataManagement.historical_data_workflow_action_policy(context)
  end

  @spec telemetry_historical_data_workflow_stage_action_policy(map(), atom() | binary()) ::
          TelemetryDataManagement.historical_data_workflow_action_decision()
  def telemetry_historical_data_workflow_stage_action_policy(context, stage)
      when is_map(context) and (is_atom(stage) or is_binary(stage)) do
    TelemetryDataManagement.historical_data_workflow_stage_action_policy(context, stage)
  end

  @spec telemetry_historical_data_workflow_group_stage_action_policy(map(), atom() | binary()) ::
          TelemetryDataManagement.historical_data_workflow_action_decision()
  def telemetry_historical_data_workflow_group_stage_action_policy(context, stage)
      when is_map(context) and (is_atom(stage) or is_binary(stage)) do
    TelemetryDataManagement.historical_data_workflow_group_stage_action_policy(context, stage)
  end

  @spec telemetry_historical_data_workflow_explanation_summary(map()) ::
          TelemetryDataManagement.historical_data_workflow_explanation_summary()
  def telemetry_historical_data_workflow_explanation_summary(context) when is_map(context) do
    TelemetryDataManagement.historical_data_workflow_explanation_summary(context)
  end

  @spec record_telemetry_historical_data_workflow_group_transition(
          atom() | binary(),
          atom() | binary(),
          binary() | [Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()],
          map(),
          keyword()
        ) ::
          {:ok, [Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()], [term()]}
          | {:error, term()}
  def record_telemetry_historical_data_workflow_group_transition(
        workflow,
        stage,
        group_events,
        attrs,
        opts \\ []
      )
      when is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_group_transition(
      workflow,
      stage,
      group_events,
      attrs,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_stale_replacement_inspection(
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_stale_replacement_inspection(
        job_id,
        event_id,
        attrs,
        opts \\ []
      )
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_stale_replacement_inspection(
      job_id,
      event_id,
      attrs,
      opts
    )
  end

  @spec record_telemetry_historical_data_workflow_missing_replacement_inspection(
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_historical_data_workflow_missing_replacement_inspection(
        request_group_id,
        replacement_run_id,
        attrs,
        opts \\ []
      )
      when is_binary(request_group_id) and is_binary(replacement_run_id) and is_map(attrs) and
             is_list(opts) do
    TelemetryDataManagement.record_historical_data_workflow_missing_replacement_inspection(
      request_group_id,
      replacement_run_id,
      attrs,
      opts
    )
  end

  @spec requeue_telemetry_historical_data_workflow_stale_replacement_job(
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Jobs.Job.t(), Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()}
          | {:error, term()}
  def requeue_telemetry_historical_data_workflow_stale_replacement_job(
        job_id,
        event_id,
        attrs,
        opts \\ []
      )
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.requeue_historical_data_workflow_stale_replacement_job(
      job_id,
      event_id,
      attrs,
      opts
    )
  end

  @spec start_telemetry_historical_data_workflow_job(atom() | binary(), map(), keyword()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def start_telemetry_historical_data_workflow_job(workflow, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.start_historical_data_workflow_job(workflow, attrs, opts)
  end

  @spec apply_telemetry_observation_identity_decision(
          binary(),
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.Storage.ObservationIdentityState.t()} | {:error, term()}
  def apply_telemetry_observation_identity_decision(
        observation_identity_id,
        decision,
        attrs,
        opts \\ []
      )
      when is_binary(observation_identity_id) and (is_atom(decision) or is_binary(decision)) and
             is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.apply_observation_identity_decision(
      observation_identity_id,
      decision,
      attrs,
      opts
    )
  end

  @spec apply_telemetry_observation_identity_decisions(
          [map()],
          atom() | binary(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Telemetry.DataManagement.observation_identity_decision_batch_summary()}
          | {:error, term()}
  def apply_telemetry_observation_identity_decisions(items, decision, attrs, opts \\ [])
      when is_list(items) and (is_atom(decision) or is_binary(decision)) and is_map(attrs) and
             is_list(opts) do
    TelemetryDataManagement.apply_observation_identity_decisions(items, decision, attrs, opts)
  end

  @spec list_telemetry_observation_identity_decision_events(binary(), keyword()) :: [
          Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent.t()
        ]
  def list_telemetry_observation_identity_decision_events(observation_identity_id, opts \\ [])
      when is_binary(observation_identity_id) and is_list(opts) do
    TelemetryStorage.list_observation_identity_decision_events(observation_identity_id, opts)
  end

  @spec record_telemetry_late_data_policy_decision(atom() | binary(), map(), keyword()) ::
          {:ok, Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_telemetry_late_data_policy_decision(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.record_late_data_policy_decision(decision, attrs, opts)
  end

  @spec execute_telemetry_late_data_policy(atom() | binary(), map(), keyword()) ::
          {:ok, TelemetryDataManagement.late_data_policy_execution_result()} | {:error, term()}
  def execute_telemetry_late_data_policy(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.execute_late_data_policy(decision, attrs, opts)
  end

  @spec telemetry_late_data_policy_execution_mode(map()) ::
          TelemetryDataManagement.late_data_policy_execution_mode()
  def telemetry_late_data_policy_execution_mode(attrs) when is_map(attrs) do
    TelemetryDataManagement.late_data_policy_execution_mode(attrs)
  end

  @spec telemetry_late_data_policy_write_opts(atom() | binary(), keyword()) ::
          {:ok, keyword()} | {:error, term()}
  def telemetry_late_data_policy_write_opts(decision, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_list(opts) do
    TelemetryDataManagement.late_data_policy_write_opts(decision, opts)
  end

  @spec runtime_health_snapshot() :: RuntimeHealth.snapshot()
  def runtime_health_snapshot do
    RuntimeHealth.snapshot()
  end

  @spec dashboard_runtime_invalidation_decisions(keyword()) :: [
          Cadence.Dashboards.RuntimeInvalidation.DecisionProjection.decision_row()
        ]
  def dashboard_runtime_invalidation_decisions(opts \\ []) when is_list(opts) do
    case durable_dashboard_runtime_invalidation_decisions(opts) do
      [] ->
        RuntimeHealth.snapshot()
        |> Dashboards.dashboard_runtime_invalidation_decisions(opts)

      decisions ->
        decisions
    end
  end

  @spec durable_dashboard_runtime_invalidation_decisions(keyword()) :: [
          Cadence.Dashboards.RuntimeInvalidation.DecisionProjection.decision_row()
        ]
  def durable_dashboard_runtime_invalidation_decisions(opts \\ []) when is_list(opts) do
    Dashboards.durable_dashboard_runtime_invalidation_decisions(opts)
  rescue
    _error -> []
  catch
    :exit, _reason -> []
  end

  @spec record_dashboard_runtime_invalidation_decision(
          Cadence.Dashboards.RuntimeInvalidation.Event.t(),
          map(),
          keyword()
        ) ::
          {:ok, Cadence.Dashboards.RuntimeInvalidation.DecisionEvent.t()} | {:error, term()}
  def record_dashboard_runtime_invalidation_decision(event, decision, opts \\ [])
      when is_map(decision) and is_list(opts) do
    Dashboards.record_dashboard_runtime_invalidation_decision(event, decision, opts)
  end

  @spec dashboard_source_capability_posture_events(
          Cadence.Dashboards.DashboardResolveResult.t(),
          keyword() | map()
        ) :: [Cadence.OperationalEvents.Event.t()]
  def dashboard_source_capability_posture_events(result, opts \\ []) do
    Dashboards.dashboard_source_capability_posture_events(result, opts)
  end

  @spec record_dashboard_source_capability_postures(
          Cadence.Dashboards.DashboardResolveResult.t(),
          keyword() | map()
        ) :: {:ok, [Cadence.OperationalEvents.Event.t()]} | {:error, term()}
  def record_dashboard_source_capability_postures(result, opts \\ []) do
    Dashboards.record_dashboard_source_capability_postures(result, opts)
  end

  @spec list_dashboard_source_capability_posture_events(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.Event.t()
        ]
  def list_dashboard_source_capability_posture_events(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Dashboards.list_dashboard_source_capability_posture_events(organization_id, mission_id, opts)
  end

  @spec reset_runtime_health() :: :ok
  def reset_runtime_health do
    RuntimeHealth.reset()
  end

  @spec replay_telemetry_evidence(binary(), binary() | [binary()], binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
  end

  @spec replay_telemetry_evidence(
          binary(),
          binary(),
          binary() | [binary()],
          binary(),
          pos_integer()
        ) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_evidence(
        organization_id,
        mission_id,
        evidence_ids,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
    end)
  end

  @spec replay_telemetry_scope(binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_scope(mission_id, %Scope{} = scope, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.replay_telemetry_scope(mission_id, scope, binding_set_id, version)
  end

  @spec replay_telemetry_scope(binary(), binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def replay_telemetry_scope(
        organization_id,
        mission_id,
        %Scope{} = scope,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.replay_telemetry_scope(mission_id, scope, binding_set_id, version)
    end)
  end

  @spec start_replay_telemetry_evidence(binary(), binary() | [binary()], binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
  end

  @spec start_replay_telemetry_evidence(
          binary(),
          binary(),
          binary() | [binary()],
          binary(),
          pos_integer()
        ) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_evidence(
        organization_id,
        mission_id,
        evidence_ids,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
    end)
  end

  @spec start_replay_telemetry_scope(binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_scope(mission_id, %Scope{} = scope, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    Replay.start_replay_telemetry_scope(mission_id, scope, binding_set_id, version)
  end

  @spec start_replay_telemetry_scope(binary(), binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def start_replay_telemetry_scope(
        organization_id,
        mission_id,
        %Scope{} = scope,
        binding_set_id,
        version
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(version) and version > 0 do
    with_mission_scope(organization_id, mission_id, fn ->
      Replay.start_replay_telemetry_scope(mission_id, scope, binding_set_id, version)
    end)
  end

  @spec fetch_replay_run(binary()) :: {:ok, Cadence.Replay.Run.t()} | {:error, term()}
  def fetch_replay_run(replay_run_id) when is_binary(replay_run_id) do
    ReplayReads.fetch_run(replay_run_id)
  end

  @spec list_replay_runs(binary(), binary(), keyword()) :: [Cadence.Replay.Run.t()]
  def list_replay_runs(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ReplayReads.list_runs(organization_id, mission_id, opts)
  end

  @spec replay_telemetry_samples(binary(), keyword()) :: [Cadence.Telemetry.Sample.t()]
  def replay_telemetry_samples(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.telemetry_samples(replay_run_id, opts)
  end

  @spec replay_managed_capability_records(binary(), keyword()) ::
          [Cadence.Runtime.ManagedCapabilityRecord.t()]
  def replay_managed_capability_records(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.managed_capability_records(replay_run_id, opts)
  end

  @spec replay_managed_action_requests(binary(), keyword()) ::
          [Cadence.Runtime.ManagedActionRequest.t()]
  def replay_managed_action_requests(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.managed_action_requests(replay_run_id, opts)
  end

  @spec replay_managed_timer_events(binary(), keyword()) ::
          [Cadence.Runtime.ManagedTimerEvent.t()]
  def replay_managed_timer_events(replay_run_id, opts \\ [])
      when is_binary(replay_run_id) and is_list(opts) do
    ReplayReads.managed_timer_events(replay_run_id, opts)
  end

  @spec fetch_background_job(binary()) :: {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_background_job(job_id) when is_binary(job_id) do
    Jobs.fetch_job(job_id)
  end

  @spec fetch_replay_job(binary()) :: {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_replay_job(replay_run_id) when is_binary(replay_run_id) do
    Jobs.fetch_job_for_run(:replay_telemetry_scope, replay_run_id)
  end

  @spec fetch_telemetry_historical_data_workflow_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_telemetry_historical_data_workflow_job(workflow_run_id)
      when is_binary(workflow_run_id) do
    Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, workflow_run_id)
  end

  @spec retry_telemetry_historical_data_workflow_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def retry_telemetry_historical_data_workflow_job(job_id) when is_binary(job_id) do
    with {:ok, %{job_type: :telemetry_historical_data_workflow}} <- Jobs.fetch_job(job_id),
         {:ok, retried_job} <- Jobs.retry_failed_job(job_id) do
      {:ok, retried_job}
    else
      {:ok, %{job_type: job_type}} ->
        {:error, {:unexpected_job_type, job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec retry_telemetry_historical_data_workflow_job(binary(), binary(), map(), keyword()) ::
          {:ok, Cadence.Jobs.Job.t(), Cadence.Telemetry.Storage.BackfillLifecycleEvent.t()}
          | {:error, term()}
  def retry_telemetry_historical_data_workflow_job(job_id, event_id, attrs, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.retry_historical_data_workflow_job(job_id, event_id, attrs, opts)
  end

  @spec retry_telemetry_historical_data_workflow_group_failed_jobs(binary(), map(), keyword()) ::
          {:ok, Cadence.Telemetry.DataManagement.historical_data_workflow_group_retry_summary()}
          | {:error, term()}
  def retry_telemetry_historical_data_workflow_group_failed_jobs(
        request_group_id,
        attrs,
        opts \\ []
      )
      when is_binary(request_group_id) and is_map(attrs) and is_list(opts) do
    TelemetryDataManagement.retry_historical_data_workflow_group_failed_jobs(
      request_group_id,
      attrs,
      opts
    )
  end

  @spec evaluate_derived_telemetry(binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def evaluate_derived_telemetry(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryService.evaluate(mission_id, opts)
  end

  @spec evaluate_derived_telemetry(binary(), binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def evaluate_derived_telemetry(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryService.evaluate(mission_id, opts)
    end)
  end

  @spec start_evaluate_derived_telemetry(binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def start_evaluate_derived_telemetry(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryService.start_evaluate(mission_id, opts)
  end

  @spec start_evaluate_derived_telemetry(binary(), binary(), keyword()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def start_evaluate_derived_telemetry(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryService.start_evaluate(mission_id, opts)
    end)
  end

  @spec fetch_derived_telemetry_run(binary()) ::
          {:ok, Cadence.DerivedTelemetry.Run.t()} | {:error, term()}
  def fetch_derived_telemetry_run(derived_run_id) when is_binary(derived_run_id) do
    DerivedTelemetryService.fetch_run(derived_run_id)
  end

  @spec fetch_derived_telemetry_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_derived_telemetry_job(derived_run_id) when is_binary(derived_run_id) do
    Jobs.fetch_job_for_run(:derived_telemetry_evaluation, derived_run_id)
  end

  @spec rebuild_latest_derived_telemetry_values(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_derived_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryLatestValueProjection.rebuild(mission_id, opts)
  end

  @spec rebuild_latest_derived_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_derived_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryLatestValueProjection.rebuild(mission_id, opts)
    end)
  end

  @spec start_rebuild_latest_derived_telemetry_values(binary(), keyword()) ::
          {:ok, Cadence.Projections.DerivedTelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_derived_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    DerivedTelemetryLatestValueProjection.start_rebuild(mission_id, opts)
  end

  @spec start_rebuild_latest_derived_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.DerivedTelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_derived_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      DerivedTelemetryLatestValueProjection.start_rebuild(mission_id, opts)
    end)
  end

  @spec fetch_latest_derived_telemetry_value_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.DerivedTelemetryLatestValues.Run.t()} | {:error, term()}
  def fetch_latest_derived_telemetry_value_rebuild_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    DerivedTelemetryLatestValueProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_derived_telemetry_value_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_derived_telemetry_value_rebuild_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:derived_telemetry_latest_value_rebuild, rebuild_run_id)
  end

  @spec diff_replay_run(binary()) :: Cadence.Replay.Diff.report()
  def diff_replay_run(replay_run_id) when is_binary(replay_run_id) do
    ReplayDiff.diff_run(replay_run_id)
  end

  @spec evaluate_telemetry_limits(binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def evaluate_telemetry_limits(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    LimitsService.evaluate(mission_id, opts)
  end

  @spec evaluate_telemetry_limits(binary(), binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def evaluate_telemetry_limits(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      LimitsService.evaluate(mission_id, opts)
    end)
  end

  @spec start_evaluate_telemetry_limits(binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def start_evaluate_telemetry_limits(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    LimitsService.start_evaluate(mission_id, opts)
  end

  @spec start_evaluate_telemetry_limits(binary(), binary(), keyword()) ::
          {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def start_evaluate_telemetry_limits(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      LimitsService.start_evaluate(mission_id, opts)
    end)
  end

  @spec fetch_telemetry_limit_run(binary()) :: {:ok, Cadence.Limits.Run.t()} | {:error, term()}
  def fetch_telemetry_limit_run(limit_run_id) when is_binary(limit_run_id) do
    LimitsService.fetch_run(limit_run_id)
  end

  @spec fetch_telemetry_limit_job(binary()) :: {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_telemetry_limit_job(limit_run_id) when is_binary(limit_run_id) do
    Jobs.fetch_job_for_run(:telemetry_limit_evaluation, limit_run_id)
  end

  @spec rebuild_latest_telemetry_values(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestValueProjection.rebuild(mission_id, opts)
  end

  @spec rebuild_latest_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestValueProjection.rebuild(mission_id, opts)
    end)
  end

  @spec start_rebuild_latest_telemetry_values(binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestValueProjection.start_rebuild(mission_id, opts)
  end

  @spec start_rebuild_latest_telemetry_values(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestValues.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_values(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestValueProjection.start_rebuild(mission_id, opts)
    end)
  end

  @spec fetch_latest_telemetry_value_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.TelemetryLatestValues.Run.t()} | {:error, term()}
  def fetch_latest_telemetry_value_rebuild_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    TelemetryLatestValueProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_telemetry_value_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_telemetry_value_rebuild_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:telemetry_latest_value_rebuild, rebuild_run_id)
  end

  @spec rebuild_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.rebuild(mission_id, opts)
  end

  @spec rebuild_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def rebuild_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.rebuild(mission_id, opts)
    end)
  end

  @spec refresh_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.refresh_from_latest_values(mission_id, opts)
  end

  @spec refresh_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def refresh_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.refresh_from_latest_values(mission_id, opts)
    end)
  end

  @spec start_rebuild_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.start_rebuild(mission_id, opts)
  end

  @spec start_rebuild_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_rebuild_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.start_rebuild(mission_id, opts)
    end)
  end

  @spec start_refresh_latest_telemetry_limit_states(binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_refresh_latest_telemetry_limit_states(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    TelemetryLatestLimitStateProjection.start_refresh_from_latest_values(mission_id, opts)
  end

  @spec start_refresh_latest_telemetry_limit_states(binary(), binary(), keyword()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def start_refresh_latest_telemetry_limit_states(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    with_mission_scope(organization_id, mission_id, fn ->
      TelemetryLatestLimitStateProjection.start_refresh_from_latest_values(mission_id, opts)
    end)
  end

  @spec fetch_latest_telemetry_limit_state_rebuild_run(binary()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_rebuild_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    TelemetryLatestLimitStateProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_telemetry_limit_state_refresh_run(binary()) ::
          {:ok, Cadence.Projections.TelemetryLatestLimitStates.Run.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_refresh_run(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    TelemetryLatestLimitStateProjection.fetch_run(rebuild_run_id)
  end

  @spec fetch_latest_telemetry_limit_state_rebuild_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_rebuild_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:telemetry_latest_limit_state_rebuild, rebuild_run_id)
  end

  @spec fetch_latest_telemetry_limit_state_refresh_job(binary()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def fetch_latest_telemetry_limit_state_refresh_job(rebuild_run_id)
      when is_binary(rebuild_run_id) do
    Jobs.fetch_job_for_run(:telemetry_latest_limit_state_refresh, rebuild_run_id)
  end

  defp with_mission_scope(organization_id, mission_id, fun)
       when is_binary(organization_id) and is_binary(mission_id) and is_function(fun, 0) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      fun.()
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family} = raw_evidence)
       when protocol_family in [:space_packet, :packet, :space_packet_stream] do
    with {:ok, %PacketRecord{} = packet_record} <- SpacePacketDecoder.decode(raw_evidence) do
      {:ok,
       %{
         packet_records: [packet_record],
         transfer_frame_records: [],
         protocol_anomalies: []
       }}
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family} = raw_evidence)
       when protocol_family in [:tm, :tm_transfer_frame] do
    with {:ok, pipeline_state} <- TMFrameIngress.init(),
         {:ok, tm_result, <<>>, _pipeline_state, _continuity_state} <-
           TMFrameIngress.process(raw_evidence, pipeline_state, %{}, <<>>) do
      {:ok, tm_result}
    else
      {:ok, _tm_result, rest, _pipeline_state, _continuity_state} ->
        {:error, {:incomplete_tm_frame_bytes, byte_size(rest)}}
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family}) do
    {:error, {:unsupported_ingress_protocol_family, protocol_family}}
  end

  defp execute_dispatches(
         %{
           packet_records: packet_records,
           transfer_frame_records: transfer_frame_records,
           protocol_anomalies: protocol_anomalies
         },
         %BindingSet{} = binding_set
       ) do
    with {:ok, dispatch_results} <- execute_dispatches(packet_records, binding_set) do
      {:ok,
       %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies,
         dispatch_results: dispatch_results
       }}
    end
  end

  defp execute_dispatches(packet_records, %BindingSet{} = binding_set)
       when is_list(packet_records) do
    Enum.reduce_while(packet_records, {:ok, []}, fn %PacketRecord{} = packet_record, {:ok, acc} ->
      with {:ok, %DispatchDecision{} = dispatch_decision} <-
             Dispatcher.dispatch(packet_record, binding_set),
           {:ok, outputs} <- Dispatcher.execute(packet_record, dispatch_decision) do
        {:cont,
         {:ok,
          acc ++
            [
              %{
                packet_record: packet_record,
                dispatch_decision: dispatch_decision,
                outputs: outputs
              }
            ]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_processing_result(%RawEvidence{} = raw_evidence, %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies,
         dispatch_results: dispatch_results
       }) do
    dispatch_decisions = Enum.map(dispatch_results, & &1.dispatch_decision)
    outputs = Enum.flat_map(dispatch_results, & &1.outputs)

    %{
      raw_evidence: raw_evidence,
      packet_records: packet_records,
      transfer_frame_records: transfer_frame_records,
      protocol_anomalies: protocol_anomalies,
      dispatch_decisions: dispatch_decisions,
      outputs: outputs,
      runtime_records: %{capability_records: [], action_requests: [], timer_events: []}
    }
  end

  defp validate_binding_set_mission(
         %RawEvidence{mission_id: mission_id},
         %BindingSet{mission_id: mission_id}
       ),
       do: :ok

  defp validate_binding_set_mission(
         %RawEvidence{mission_id: evidence_mission_id},
         %BindingSet{mission_id: binding_set_mission_id}
       ) do
    {:error, {:binding_set_mission_mismatch, evidence_mission_id, binding_set_mission_id}}
  end
end
