defmodule Cadence.Projections.MissionEvents do
  @moduledoc """
  Rebuildable mission timeline projection over selected canonical record
  families.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Contacts.{CombinedDownlinkRecord, ContactAction, ContactStore, DownlinkDiagnostic}
  alias Cadence.Jobs
  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Persistence.Schemas.{
    CombinedDownlinkRecordRow,
    DownlinkDiagnosticRow,
    ManagedActionRequestRow,
    MissionEventRow,
    TelemetryLimitEventRow
  }

  alias Cadence.Projections.MissionEvents.{RebuildRunRow, Run}
  alias Cadence.Repo
  alias Cadence.Runtime.ManagedActionRequest

  @spec project(OperationalEvent.t()) :: [Entry.t()]
  def project(%OperationalEvent{kind: :binding_set_activated} = event) do
    [
      Entry.new(%{
        mission_event_id: "mission_event:#{event.event_id}",
        mission_id: event.mission_id,
        occurred_at: event.effective_at || event.occurred_at,
        category: :runtime,
        kind: :binding_set_activated,
        severity: event.severity || :info,
        status: "active",
        title: "Binding Set Activated",
        summary:
          "Activated " <>
            payload_text(event, :binding_set_id) <>
            " v" <> payload_text(event, :binding_set_version),
        source_record_kind: :operational_event,
        source_record_id: event.event_id,
        subject_kind: :binding_set,
        subject_id: payload_text(event, :binding_set_id),
        correlation_key: payload_text(event, :binding_set_id),
        spacecraft_id: operational_event_text(event, :spacecraft_id),
        source_endpoint_ref: operational_event_text(event, :source_endpoint_ref),
        activation_id: payload_text(event, :activation_id),
        actor: event.actor,
        metadata:
          event.metadata
          |> Map.merge(%{
            "operational_event_id" => event.event_id,
            "source_record_kind" => causality_text(event, :source_record_kind),
            "source_record_id" => causality_text(event, :source_record_id),
            "binding_set_id" => payload_text(event, :binding_set_id),
            "binding_set_version" => payload_value(event, :binding_set_version),
            "generation" => payload_value(event, :generation),
            "binding_set_content_sha256" => payload_text(event, :binding_set_content_sha256)
          })
      })
    ]
  end

  def project(%OperationalEvent{kind: kind} = event)
      when kind in [
             :managed_capability_initialized,
             :managed_capability_record_handled,
             :managed_capability_timer_handled,
             :managed_action_requested,
             :managed_timer_scheduled,
             :managed_timer_fired,
             :managed_timer_canceled
           ] do
    [
      Entry.new(%{
        mission_event_id: "mission_event:#{event.event_id}",
        mission_id: event.mission_id,
        occurred_at: event.effective_at || event.occurred_at,
        category: :runtime,
        kind: kind,
        severity: event.severity || :info,
        status: managed_runtime_status(event),
        title: managed_runtime_title(kind),
        summary: managed_runtime_summary(event),
        source_record_kind: :operational_event,
        source_record_id: event.event_id,
        subject_kind: :capability_instance,
        subject_id: payload_text(event, :capability_instance_id),
        correlation_key: payload_text(event, :capability_instance_id),
        spacecraft_id: operational_event_text(event, :spacecraft_id),
        source_endpoint_ref: managed_runtime_source_endpoint_ref(event),
        capability_instance_id: payload_text(event, :capability_instance_id),
        activation_id: payload_text(event, :activation_id),
        actor: event.actor,
        metadata:
          event.metadata
          |> Map.merge(%{
            "operational_event_id" => event.event_id,
            "source_record_kind" => causality_text(event, :source_record_kind),
            "source_record_id" => causality_text(event, :source_record_id),
            "replay_run_id" => causality_text(event, :replay_run_id),
            "family_key" => payload_text(event, :family_key),
            "event_kind" => payload_text(event, :event_kind),
            "action_kind" => payload_text(event, :action_kind),
            "timer_key" => payload_text(event, :timer_key),
            "partition_affinity" => payload_text(event, :partition_affinity),
            "partition_value" => payload_text(event, :partition_value),
            "packet_id" => payload_text(event, :packet_id),
            "evidence_id" => payload_text(event, :evidence_id)
          })
          |> compact_metadata()
      })
    ]
  end

  @spec project(BindingSetActivation.t()) :: [Entry.t()]
  def project(%BindingSetActivation{} = activation) do
    activation
    |> OperationalEvent.from_binding_set_activation()
    |> project()
  end

  @spec project(ContactAction.t()) :: [Entry.t()]
  def project(%ContactAction{} = contact_action) do
    [
      Entry.new(%{
        mission_id: contact_action.mission_id,
        occurred_at: contact_action.occurred_at,
        category: :operations,
        kind: contact_action.action_kind,
        severity: :info,
        status: contact_action_status(contact_action.action_kind),
        title: contact_action_title(contact_action.action_kind),
        summary: contact_action.reason,
        source_record_kind: :contact_action,
        source_record_id: contact_action.contact_action_id,
        subject_kind: contact_action_subject_kind(contact_action),
        subject_id: contact_action_subject_id(contact_action),
        correlation_key:
          contact_action.realized_contact_id || contact_action.scheduled_contact_id,
        scheduled_contact_id: contact_action.scheduled_contact_id,
        realized_contact_id: contact_action.realized_contact_id,
        actor: contact_action.actor,
        metadata: contact_action.metadata
      })
    ]
  end

  @spec project(LimitEvent.t()) :: [Entry.t()]
  def project(%LimitEvent{violation: false}), do: []

  def project(%LimitEvent{} = limit_event) do
    [
      Entry.new(%{
        mission_id: limit_event.mission_id,
        occurred_at: limit_event.receipt_time,
        category: :health,
        kind: :limit_violation,
        severity: limit_event_severity(limit_event.normalized_state),
        status: Atom.to_string(limit_event.limit_state),
        title: limit_event.point_name <> " limit violation",
        summary:
          Atom.to_string(limit_event.normalized_state) <>
            " in " <> limit_event.limit_set_name,
        source_record_kind: :limit_event,
        source_record_id: limit_event.limit_event_id,
        subject_kind: :telemetry_point,
        subject_id: limit_event.point_id,
        correlation_key: limit_event.point_id,
        spacecraft_id: limit_event.spacecraft_id,
        metadata:
          Map.merge(limit_event.provenance, %{
            "evaluated_value" => limit_event.evaluated_value,
            "limit_definition_id" => limit_event.limit_definition_id,
            "limit_definition_version" => limit_event.limit_definition_version,
            "limit_set_name" => limit_event.limit_set_name,
            "normalized_state" => Atom.to_string(limit_event.normalized_state),
            "source_sample_type" => Atom.to_string(limit_event.source_sample_type),
            "sample_id" => limit_event.sample_id
          })
      })
    ]
  end

  @spec project(ManagedActionRequest.t()) :: [Entry.t()]
  def project(%ManagedActionRequest{} = action_request) do
    [
      Entry.new(%{
        mission_id: action_request.mission_id,
        occurred_at: action_request.requested_at,
        category: :runtime,
        kind: :managed_action_requested,
        severity: :info,
        status: Atom.to_string(action_request.action_kind),
        title: "Managed Action Requested",
        summary:
          Atom.to_string(action_request.family_key) <>
            " requested " <> Atom.to_string(action_request.action_kind),
        source_record_kind: :managed_action_request,
        source_record_id: action_request.action_request_id,
        subject_kind: :capability_instance,
        subject_id: action_request.capability_instance_id,
        correlation_key: action_request.capability_instance_id,
        capability_instance_id: action_request.capability_instance_id,
        activation_id: action_request.activation_id,
        metadata:
          Map.merge(action_request.request_document, %{
            "family_key" => Atom.to_string(action_request.family_key),
            "partition_affinity" => Atom.to_string(action_request.partition_affinity),
            "partition_value" => action_request.partition_value,
            "packet_id" => action_request.packet_id,
            "evidence_id" => action_request.evidence_id,
            "action_kind" => Atom.to_string(action_request.action_kind)
          })
      })
    ]
  end

  @spec project(CombinedDownlinkRecord.t()) :: [Entry.t()]
  def project(%CombinedDownlinkRecord{} = combined_record) do
    [
      Entry.new(%{
        mission_id: combined_record.mission_id,
        occurred_at: combined_record.observed_at,
        category: :transport,
        kind: :downlink_record_combined,
        severity: :info,
        status: Atom.to_string(combined_record.selected_reason),
        title: "Downlink Record Combined",
        summary: "Selected path " <> combined_record.selected_path_id,
        source_record_kind: :combined_downlink_record,
        source_record_id: combined_record.merged_record_id,
        subject_kind: :downlink_observation,
        subject_id: combined_record.selected_observation_id,
        correlation_key: combined_record.observation_key,
        source_endpoint_ref: combined_record.source_endpoint_ref,
        realized_contact_id: combined_record.realized_contact_id,
        path_id: combined_record.selected_path_id,
        metadata:
          Map.merge(combined_record.metadata, %{
            "observation_key" => combined_record.observation_key,
            "payload" => combined_record.payload,
            "selected_observation_id" => combined_record.selected_observation_id,
            "selected_reason" => Atom.to_string(combined_record.selected_reason)
          })
      })
    ]
  end

  @spec project(DownlinkDiagnostic.t()) :: [Entry.t()]
  def project(%DownlinkDiagnostic{} = diagnostic) do
    {kind, title} = downlink_diagnostic_descriptor(diagnostic.diagnostic_kind)

    [
      Entry.new(%{
        mission_id: diagnostic.mission_id,
        occurred_at: diagnostic.recorded_at,
        category: :transport,
        kind: kind,
        severity: :info,
        status: Atom.to_string(diagnostic.diagnostic_kind),
        title: title,
        summary: "Path " <> diagnostic.path_id <> " vs selected " <> diagnostic.selected_path_id,
        source_record_kind: :downlink_diagnostic,
        source_record_id: diagnostic.diagnostic_id,
        subject_kind: :downlink_observation,
        subject_id: diagnostic.observation_id,
        correlation_key: diagnostic.observation_key,
        realized_contact_id: diagnostic.realized_contact_id,
        path_id: diagnostic.path_id,
        metadata:
          Map.merge(diagnostic.metadata, %{
            "observation_key" => diagnostic.observation_key,
            "selected_path_id" => diagnostic.selected_path_id,
            "competing_observation_id" => diagnostic.competing_observation_id,
            "diagnostic_kind" => Atom.to_string(diagnostic.diagnostic_kind)
          })
      })
    ]
  end

  def project(_record), do: []

  @spec project_many([term()]) :: [Entry.t()]
  def project_many(records) when is_list(records) do
    records
    |> Enum.flat_map(&project/1)
    |> Enum.sort_by(fn %Entry{} = entry ->
      {DateTime.to_unix(entry.occurred_at, :microsecond), entry.mission_event_id}
    end)
  end

  @spec persist_entries(module(), [Entry.t()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def persist_entries(_repo, []), do: {:ok, 0}

  def persist_entries(repo, entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, 0}, fn %Entry{} = entry, {:ok, count} ->
      case upsert_entry(repo, entry) do
        {:ok, _row} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec rebuild(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild(mission_id) when is_binary(mission_id) do
    run = Run.new(%{mission_id: mission_id})

    with {:ok, persisted_run} <- insert_run(run),
         {:ok, completed_run} <- execute_rebuild(persisted_run) do
      {:ok, completed_run.rebuilt_event_count}
    end
  end

  @spec start_rebuild(binary()) :: {:ok, Run.t()} | {:error, term()}
  def start_rebuild(mission_id) when is_binary(mission_id) do
    run = Run.new(%{mission_id: mission_id})

    with {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :mission_event_rebuild,
             mission_id,
             persisted_run.rebuild_run_id,
             %{"rebuild_run_id" => persisted_run.rebuild_run_id}
           ) do
        {:ok, _job} ->
          {:ok, persisted_run}

        {:error, reason} ->
          failed_run =
            %Run{
              persisted_run
              | status: :failed,
                failure_reason: {:job_enqueue_failed, reason},
                completed_at: DateTime.utc_now()
            }

          _ = update_run(failed_run)
          {:error, reason}
      end
    end
  end

  @spec fetch_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def fetch_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    case Repo.get(RebuildRunRow, rebuild_run_id) do
      nil ->
        {:error, :mission_event_rebuild_run_not_found}

      %RebuildRunRow{} = row ->
        {:ok, RebuildRunRow.to_domain(row)}
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_run(rebuild_run_id) when is_binary(rebuild_run_id) do
    with {:ok, %Run{} = run} <- fetch_run(rebuild_run_id) do
      execute_rebuild(run)
    end
  end

  defp upsert_entry(repo, %Entry{} = entry) do
    repo.insert(
      MissionEventRow.changeset(entry),
      on_conflict: {:replace, MissionEventRow.upsert_fields()},
      conflict_target: [:mission_event_id]
    )
  end

  defp execute_rebuild(%Run{} = run) do
    mission_id = run.mission_id

    entries =
      load_source_entries(mission_id)
      |> project_many()

    Repo.transaction(fn ->
      MissionEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.delete_all()

      Enum.each(entries, fn %Entry{} = entry ->
        entry
        |> MissionEventRow.changeset()
        |> Repo.insert!(
          on_conflict: {:replace, MissionEventRow.upsert_fields()},
          conflict_target: [:mission_event_id]
        )
      end)
    end)
    |> case do
      {:ok, _result} ->
        completed_run =
          %Run{
            run
            | status: :completed,
              rebuilt_event_count: length(entries),
              completed_at: DateTime.utc_now()
          }

        update_run(completed_run)

      {:error, reason} ->
        failed_run =
          %Run{
            run
            | status: :failed,
              failure_reason: reason,
              completed_at: DateTime.utc_now()
          }

        _ = update_run(failed_run)
        {:error, reason}
    end
  rescue
    exception ->
      failed_run =
        %Run{
          run
          | status: :failed,
            failure_reason: {:exception, Exception.message(exception)},
            completed_at: DateTime.utc_now()
        }

      _ = update_run(failed_run)
      {:error, {:exception, exception}}
  catch
    kind, reason ->
      failed_run =
        %Run{
          run
          | status: :failed,
            failure_reason: {kind, reason},
            completed_at: DateTime.utc_now()
        }

      _ = update_run(failed_run)
      {:error, {kind, reason}}
  end

  defp load_source_entries(mission_id) do
    contact_actions = ContactStore.list_actions(mission_id, [])

    limit_events =
      TelemetryLimitEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()
      |> Enum.map(&TelemetryLimitEventRow.to_domain/1)

    managed_action_requests =
      ManagedActionRequestRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()
      |> Enum.map(&ManagedActionRequestRow.to_domain/1)

    combined_records =
      CombinedDownlinkRecordRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()
      |> Enum.map(&CombinedDownlinkRecordRow.to_domain/1)

    diagnostics =
      DownlinkDiagnosticRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.all()
      |> Enum.map(&DownlinkDiagnosticRow.to_domain/1)

    operational_events = OperationalEvents.list_all_events(mission_id)

    operational_events ++
      contact_actions ++
      limit_events ++ managed_action_requests ++ combined_records ++ diagnostics
  end

  defp payload_value(%OperationalEvent{payload: payload}, key) when is_atom(key) do
    case Map.fetch(payload, key) do
      {:ok, value} -> value
      :error -> Map.get(payload, Atom.to_string(key))
    end
  end

  defp payload_text(%OperationalEvent{} = event, key), do: text_value(payload_value(event, key))

  defp operational_event_text(%OperationalEvent{} = event, key) when is_atom(key) do
    event.scope
    |> map_value(key)
    |> fallback(payload_value(event, key))
    |> fallback(map_value(event.current, key))
    |> text_value()
  end

  defp causality_text(%OperationalEvent{causality: causality}, key) do
    causality
    |> map_value(key)
    |> text_value()
  end

  defp managed_runtime_status(%OperationalEvent{kind: :managed_action_requested} = event),
    do: payload_text(event, :action_kind)

  defp managed_runtime_status(%OperationalEvent{} = event),
    do: payload_text(event, :event_kind)

  defp managed_runtime_title(:managed_capability_initialized),
    do: "Managed Capability Initialized"

  defp managed_runtime_title(:managed_capability_record_handled), do: "Managed Record Handled"
  defp managed_runtime_title(:managed_capability_timer_handled), do: "Managed Timer Handled"
  defp managed_runtime_title(:managed_action_requested), do: "Managed Action Requested"
  defp managed_runtime_title(:managed_timer_scheduled), do: "Managed Timer Scheduled"
  defp managed_runtime_title(:managed_timer_fired), do: "Managed Timer Fired"
  defp managed_runtime_title(:managed_timer_canceled), do: "Managed Timer Canceled"

  defp managed_runtime_summary(%OperationalEvent{kind: :managed_action_requested} = event) do
    [payload_text(event, :family_key), "requested", payload_text(event, :action_kind)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp managed_runtime_summary(%OperationalEvent{} = event) do
    [payload_text(event, :family_key), payload_text(event, :event_kind)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp managed_runtime_source_endpoint_ref(%OperationalEvent{} = event) do
    if payload_text(event, :partition_affinity) == "source_endpoint" do
      payload_text(event, :partition_value)
    end
  end

  defp compact_metadata(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
    |> Map.new()
  end

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fallback(nil, fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp text_value(nil), do: nil
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)

  defp contact_action_title(:scheduled_contact_canceled), do: "Scheduled Contact Canceled"
  defp contact_action_title(:realized_contact_ended_early), do: "Realized Contact Ended Early"

  defp contact_action_status(:scheduled_contact_canceled), do: "canceled"
  defp contact_action_status(:realized_contact_ended_early), do: "ended_early"

  defp contact_action_subject_kind(%ContactAction{realized_contact_id: realized_contact_id})
       when is_binary(realized_contact_id),
       do: :realized_contact

  defp contact_action_subject_kind(%ContactAction{scheduled_contact_id: scheduled_contact_id})
       when is_binary(scheduled_contact_id),
       do: :scheduled_contact

  defp contact_action_subject_kind(_contact_action), do: nil

  defp contact_action_subject_id(%ContactAction{realized_contact_id: realized_contact_id})
       when is_binary(realized_contact_id),
       do: realized_contact_id

  defp contact_action_subject_id(%ContactAction{scheduled_contact_id: scheduled_contact_id})
       when is_binary(scheduled_contact_id),
       do: scheduled_contact_id

  defp contact_action_subject_id(_contact_action), do: nil

  defp limit_event_severity(:red), do: :critical
  defp limit_event_severity(:yellow), do: :warning
  defp limit_event_severity(:green), do: :info
  defp limit_event_severity(:blue), do: :info

  defp downlink_diagnostic_descriptor(:accepted),
    do: {:downlink_observation_accepted, "Downlink Observation Accepted"}

  defp downlink_diagnostic_descriptor(_diagnostic_kind),
    do: {:downlink_selection_changed, "Downlink Selection Changed"}

  defp insert_run(%Run{} = run) do
    case Repo.insert(RebuildRunRow.changeset(run)) do
      {:ok, %RebuildRunRow{} = run_row} ->
        {:ok, RebuildRunRow.to_domain(run_row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case Repo.get(RebuildRunRow, run.rebuild_run_id) do
      nil ->
        {:error, :mission_event_rebuild_run_not_found}

      %RebuildRunRow{} = run_row ->
        case Repo.update(RebuildRunRow.changeset(run_row, run)) do
          {:ok, %RebuildRunRow{} = updated_row} ->
            {:ok, RebuildRunRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
