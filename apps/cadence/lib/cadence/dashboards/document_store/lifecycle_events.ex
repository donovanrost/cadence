defmodule Cadence.Dashboards.DocumentStore.LifecycleEvents do
  @moduledoc false

  import Ecto.Query

  alias Cadence.Dashboards.{ComparisonReviewQueue, LifecycleEvent}
  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Dashboards.DocumentStore.LifecycleEventRow, as: DashboardLifecycleEventRow
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Repo
  alias Ecto.Changeset

  @spec list_lifecycle_events(binary(), binary(), binary()) :: [LifecycleEvent.t()]
  def list_lifecycle_events(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DashboardLifecycleEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_id == ^dashboard_id
    )
    |> order_by([row], asc: row.occurred_at, asc: row.dashboard_lifecycle_event_id)
    |> Repo.all()
    |> Enum.map(&DashboardLifecycleEventRow.to_domain/1)
  end

  @spec fetch_lifecycle_event(binary(), binary(), binary()) ::
          {:ok, LifecycleEvent.t()} | {:error, :not_found}
  def fetch_lifecycle_event(organization_id, mission_id, dashboard_lifecycle_event_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(dashboard_lifecycle_event_id) do
    DashboardLifecycleEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_lifecycle_event_id == ^dashboard_lifecycle_event_id
    )
    |> Repo.one()
    |> case do
      %DashboardLifecycleEventRow{} = row -> {:ok, DashboardLifecycleEventRow.to_domain(row)}
      nil -> {:error, :not_found}
    end
  end

  @spec list_open_comparison_review_requests(binary(), binary(), binary()) :: [LifecycleEvent.t()]
  def list_open_comparison_review_requests(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    events = list_comparison_review_events(organization_id, mission_id, dashboard_id)

    ComparisonReviewQueue.open_requests(events)
  end

  @spec comparison_review_queue(binary(), binary(), binary()) ::
          ComparisonReviewQueue.open_summary()
  def comparison_review_queue(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    organization_id
    |> list_comparison_review_events(mission_id, dashboard_id)
    |> ComparisonReviewQueue.open_summary()
  end

  @spec record_comparison_review_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_comparison_review_request(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    transaction_with_dashboard_lock(organization_id, mission_id, dashboard_id, fn row ->
      record_comparison_review_request_for_row(
        row,
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts
      )
    end)
  end

  defp record_comparison_review_request_for_row(
         %OpsDashboardRow{} = row,
         organization_id,
         mission_id,
         dashboard_id,
         payload,
         opts
       ) do
    with :ok <- reject_archived(row),
         :ok <-
           reject_existing_open_comparison_review_request(
             organization_id,
             mission_id,
             dashboard_id,
             payload
           ) do
      insert(
        row,
        row,
        :comparison_review_requested,
        event_time(opts),
        Keyword.merge(opts, payload: comparison_review_request_payload(row, payload))
      )
    end
  end

  defp transaction_with_dashboard_lock(organization_id, mission_id, dashboard_id, fun)
       when is_function(fun, 1) do
    Repo.transaction(fn ->
      organization_id
      |> get_row_for_update(mission_id, dashboard_id)
      |> case do
        nil -> {:error, :dashboard_not_found}
        %OpsDashboardRow{} = row -> fun.(row)
      end
    end)
    |> unwrap_transaction_result()
  end

  @spec record_comparison_review_resolution(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_comparison_review_resolution(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    transaction_with_dashboard_lock(organization_id, mission_id, dashboard_id, fn row ->
      record_comparison_review_resolution_for_row(
        row,
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts
      )
    end)
  end

  defp record_comparison_review_resolution_for_row(
         %OpsDashboardRow{} = row,
         organization_id,
         mission_id,
         dashboard_id,
         payload,
         opts
       ) do
    with :ok <- reject_archived(row),
         {:ok, request_event} <-
           fetch_comparison_review_request_event(
             organization_id,
             mission_id,
             dashboard_id,
             payload
           ),
         :ok <- validate_comparison_review_resolution_context(request_event, payload),
         :ok <-
           reject_existing_comparison_review_resolution(
             organization_id,
             mission_id,
             dashboard_id,
             request_event.dashboard_lifecycle_event_id
           ) do
      insert(
        row,
        row,
        :comparison_review_resolved,
        event_time(opts),
        Keyword.merge(opts,
          payload: comparison_review_resolution_payload(row, request_event, payload)
        )
      )
    end
  end

  @spec record_health_snapshot(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_health_snapshot(organization_id, mission_id, dashboard_id, snapshot, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(snapshot) and is_list(opts) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row ->
        with :ok <- reject_archived(row),
             :ok <- validate_health_snapshot(snapshot) do
          insert(
            row,
            row,
            :health_snapshot_captured,
            event_time(opts),
            Keyword.merge(opts, payload: health_snapshot_payload(row, snapshot, opts))
          )
        end
    end
  end

  @spec record_publish_readiness_check(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row ->
        with :ok <- reject_archived(row) do
          insert(
            row,
            row,
            :publish_readiness_checked,
            event_time(opts),
            Keyword.merge(opts, payload: publish_readiness_check_payload(row, payload))
          )
        end
    end
  end

  defp get_row_for_update(organization_id, mission_id, dashboard_id) do
    OpsDashboardRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_id == ^dashboard_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp get_row(organization_id, mission_id, dashboard_id) do
    Repo.get_by(OpsDashboardRow,
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id
    )
  end

  defp reject_archived(%OpsDashboardRow{} = row) do
    if OpsDashboardRow.archived?(row), do: {:error, :dashboard_archived}, else: :ok
  end

  defp unwrap_transaction_result({:ok, result}), do: result
  defp unwrap_transaction_result({:error, reason}), do: {:error, reason}

  def insert(
        %OpsDashboardRow{} = previous_row,
        %OpsDashboardRow{} = current_row,
        event_type,
        %DateTime{} = occurred_at,
        opts
      ) do
    event =
      LifecycleEvent.new(%{
        organization_id: current_row.organization_id,
        mission_id: current_row.mission_id,
        dashboard_id: current_row.dashboard_id,
        event_type: event_type,
        dashboard_version: event_dashboard_version(event_type, current_row),
        previous_lifecycle_state: previous_row.lifecycle_state,
        current_lifecycle_state: current_row.lifecycle_state,
        previous_published_version: OpsDashboardRow.published_version(previous_row),
        current_published_version: OpsDashboardRow.published_version(current_row),
        actor_id: Keyword.get(opts, :actor_id),
        occurred_at: occurred_at,
        payload: lifecycle_event_payload(previous_row, current_row, event_type, opts)
      })

    case Repo.insert(DashboardLifecycleEventRow.changeset(event)) do
      {:ok, %DashboardLifecycleEventRow{} = row} ->
        lifecycle_event = DashboardLifecycleEventRow.to_domain(row)

        with {:ok, %OperationalEvent{}} <- persist_lifecycle_operational_event(lifecycle_event) do
          {:ok, lifecycle_event}
        end

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp persist_lifecycle_operational_event(%LifecycleEvent{} = lifecycle_event) do
    lifecycle_event
    |> OperationalEvent.from_dashboard_lifecycle_event()
    |> then(&OperationalEvents.persist_event(Repo, &1))
  end

  def event_type("archived"), do: :archived
  def event_type("active"), do: :restored

  def event_time(opts) do
    opts
    |> Keyword.get(:occurred_at, DateTime.utc_now())
    |> DateTime.truncate(:microsecond)
  end

  defp event_dashboard_version(:published, %OpsDashboardRow{} = row),
    do: OpsDashboardRow.published_version(row)

  defp event_dashboard_version(_event_type, %OpsDashboardRow{} = row),
    do: OpsDashboardRow.latest_version(row)

  defp lifecycle_event_payload(previous_row, current_row, event_type, opts) do
    base_payload = %{
      "event_type" => Atom.to_string(event_type),
      "dashboard_name" => current_row.name,
      "previous" => %{
        "lifecycle_state" => previous_row.lifecycle_state,
        "published_version" => OpsDashboardRow.published_version(previous_row),
        "draft_version" => OpsDashboardRow.draft_version(previous_row),
        "latest_version" => OpsDashboardRow.latest_version(previous_row)
      },
      "current" => %{
        "lifecycle_state" => current_row.lifecycle_state,
        "published_version" => OpsDashboardRow.published_version(current_row),
        "draft_version" => OpsDashboardRow.draft_version(current_row),
        "latest_version" => OpsDashboardRow.latest_version(current_row)
      }
    }

    Map.merge(base_payload, Keyword.get(opts, :payload, %{}))
  end

  defp comparison_review_request_payload(%OpsDashboardRow{} = row, payload) do
    Map.merge(
      %{
        "schema" => "dashboard_comparison_review_request.v1",
        "request_kind" => "comparison_open_findings_review",
        "source" => "dashboard_comparison_rollup",
        "dashboard_name" => row.name
      },
      payload
    )
  end

  defp comparison_review_resolution_payload(
         %OpsDashboardRow{} = row,
         %LifecycleEvent{} = request_event,
         payload
       ) do
    %{
      "schema" => "dashboard_comparison_review_resolution.v1",
      "request_kind" => "comparison_open_findings_review",
      "source" => "dashboard_activity",
      "source_request_event_id" => request_event.dashboard_lifecycle_event_id,
      "dashboard_name" => row.name
    }
    |> Map.merge(payload)
    |> Map.merge(comparison_review_resolution_source_payload(request_event))
  end

  defp comparison_review_resolution_source_payload(%LifecycleEvent{payload: payload})
       when is_map(payload) do
    bulk_decision_summary = comparison_review_bulk_decision_source_summary(payload)

    operational_context =
      ComparisonReviewQueue.request_operational_context(%LifecycleEvent{payload: payload})

    %{
      "workflow_intent" => payload_value(payload, "workflow_intent"),
      "open_findings" => payload_value(payload, "open_findings"),
      "source_open_count" => payload_value(payload, "open_count"),
      "source_open_placement_ids" =>
        comparison_review_request_placement_ids(%LifecycleEvent{
          payload: payload
        }),
      "source_scope_kind" => Map.get(operational_context, :scope_kind),
      "source_scope_ids" => Map.get(operational_context, :scope_ids),
      "source_contact_ids" => Map.get(operational_context, :contact_ids),
      "source_resource_ids" => Map.get(operational_context, :resource_ids),
      "source_transport_ids" => Map.get(operational_context, :transport_ids),
      "source_endpoint_ids" => Map.get(operational_context, :source_endpoint_ids),
      "source_ground_station_ids" => Map.get(operational_context, :ground_station_ids),
      "source_scope_link_ids" => Map.get(operational_context, :scope_link_ids)
    }
    |> Map.merge(bulk_decision_summary)
    |> Enum.reject(fn {_key, value} -> value in [nil, [], ""] end)
    |> Map.new()
  end

  defp comparison_review_resolution_source_payload(%LifecycleEvent{}), do: %{}

  defp comparison_review_bulk_decision_source_summary(payload) when is_map(payload) do
    findings =
      payload
      |> payload_value("open_findings")
      |> payload_value("findings")
      |> case do
        findings when is_list(findings) -> findings
        _findings -> []
      end

    actionable_items =
      findings
      |> Enum.map(&comparison_review_bulk_decision_actionable_item/1)
      |> Enum.reject(&is_nil/1)

    skipped_items =
      findings
      |> Enum.map(&comparison_review_bulk_decision_skipped_item/1)
      |> Enum.reject(&is_nil/1)

    %{
      "source_bulk_decision_actionable_count" => length(actionable_items),
      "source_bulk_decision_actionable_placement_ids" =>
        comparison_review_bulk_decision_placement_ids(actionable_items),
      "source_bulk_decision_skipped_count" => length(skipped_items),
      "source_bulk_decision_skipped_placement_ids" =>
        comparison_review_bulk_decision_placement_ids(skipped_items),
      "source_bulk_decision_skipped_reasons" =>
        skipped_items
        |> Enum.map(&Map.get(&1, "reason"))
        |> Enum.filter(&present_text?/1)
        |> Enum.uniq()
    }
  end

  defp comparison_review_bulk_decision_actionable_item(finding) when is_map(finding) do
    observation_identity_id = comparison_review_observation_identity_id(finding)

    cond do
      not present_text?(observation_identity_id) ->
        nil

      payload_value(finding, "decision_status") == "applied" ->
        nil

      true ->
        %{
          "placement_id" => payload_value(finding, "placement_id"),
          "observation_identity_id" => observation_identity_id
        }
    end
  end

  defp comparison_review_bulk_decision_actionable_item(_finding), do: nil

  defp comparison_review_bulk_decision_skipped_item(finding) when is_map(finding) do
    cond do
      not present_text?(comparison_review_observation_identity_id(finding)) ->
        %{
          "placement_id" => payload_value(finding, "placement_id"),
          "reason" => "missing_observation_identity"
        }

      payload_value(finding, "decision_status") == "applied" ->
        %{
          "placement_id" => payload_value(finding, "placement_id"),
          "reason" => "already_applied"
        }

      true ->
        nil
    end
  end

  defp comparison_review_bulk_decision_skipped_item(_finding), do: nil

  defp comparison_review_observation_identity_id(finding) when is_map(finding) do
    payload_value(finding, "observation_identity_id") ||
      payload_value(finding, "primary_observation_identity_id") ||
      payload_value(finding, "compare_observation_identity_id")
  end

  defp comparison_review_bulk_decision_placement_ids(items) do
    items
    |> Enum.map(&Map.get(&1, "placement_id"))
    |> Enum.filter(&present_text?/1)
    |> Enum.uniq()
  end

  defp health_snapshot_payload(%OpsDashboardRow{} = row, snapshot, opts) do
    %{
      "schema" => "dashboard_health_snapshot_capture.v1",
      "source" => "dashboard_health_rollup",
      "dashboard_name" => row.name,
      "snapshot_id" => Map.get(snapshot, "snapshot_id"),
      "snapshot_schema" => Map.get(snapshot, "schema"),
      "health_state" => Map.get(snapshot, "state"),
      "health_severity" => Map.get(snapshot, "severity"),
      "captured_reason" => Keyword.get(opts, :captured_reason),
      "snapshot" => snapshot
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp publish_readiness_check_payload(%OpsDashboardRow{} = row, payload) do
    Map.merge(
      %{
        "schema" => "dashboard_publish_readiness_check.v1",
        "source" => "dashboard_publish_readiness",
        "dashboard_name" => row.name
      },
      payload
    )
  end

  defp validate_health_snapshot(snapshot) do
    cond do
      payload_value(snapshot, "schema") != "dashboard_health_snapshot.v1" ->
        {:error, :invalid_health_snapshot}

      payload_value(snapshot, "snapshot_id") in [nil, ""] ->
        {:error, :invalid_health_snapshot}

      true ->
        :ok
    end
  end

  defp fetch_comparison_review_request_event(
         organization_id,
         mission_id,
         dashboard_id,
         payload
       ) do
    request_event_id = payload_value(payload, "source_request_event_id")

    if request_event_id in [nil, ""] do
      {:error, :comparison_review_request_not_found}
    else
      DashboardLifecycleEventRow
      |> where(
        [event],
        event.organization_id == ^organization_id and event.mission_id == ^mission_id and
          event.dashboard_id == ^dashboard_id and
          event.dashboard_lifecycle_event_id == ^request_event_id and
          event.event_type == "comparison_review_requested"
      )
      |> Repo.one()
      |> case do
        %DashboardLifecycleEventRow{} = row ->
          {:ok, DashboardLifecycleEventRow.to_domain(row)}

        nil ->
          {:error, :comparison_review_request_not_found}
      end
    end
  end

  defp validate_comparison_review_resolution_context(%LifecycleEvent{} = request_event, payload) do
    request_placement_ids = comparison_review_request_placement_ids(request_event)
    selected_placement_id = payload_value(payload, "selected_placement_id")
    affected_placement_ids = payload |> payload_value("affected_placement_ids") |> placement_ids()

    cond do
      selected_placement_id in [nil, ""] and affected_placement_ids == [] ->
        :ok

      request_placement_ids == [] ->
        {:error, :comparison_review_resolution_context_mismatch}

      is_binary(selected_placement_id) and selected_placement_id not in request_placement_ids ->
        {:error, :comparison_review_resolution_context_mismatch}

      Enum.any?(affected_placement_ids, &(&1 not in request_placement_ids)) ->
        {:error, :comparison_review_resolution_context_mismatch}

      true ->
        :ok
    end
  end

  defp comparison_review_request_placement_ids(%LifecycleEvent{payload: payload})
       when is_map(payload) do
    ComparisonReviewQueue.request_placements(%{payload: payload})
  end

  defp comparison_review_request_placement_ids(%LifecycleEvent{}), do: []

  defp comparison_review_payload_placement_ids(payload) when is_map(payload) do
    ComparisonReviewQueue.request_placements(%{payload: payload})
  end

  defp comparison_review_payload_placement_ids(_payload), do: []

  defp reject_existing_open_comparison_review_request(
         organization_id,
         mission_id,
         dashboard_id,
         payload
       ) do
    incoming_placement_ids = comparison_review_payload_placement_ids(payload)

    if incoming_placement_ids == [] do
      :ok
    else
      organization_id
      |> list_open_comparison_review_requests(mission_id, dashboard_id)
      |> Enum.find(&comparison_review_request_overlaps?(&1, incoming_placement_ids))
      |> case do
        nil -> :ok
        %LifecycleEvent{} = event -> {:error, {:comparison_review_already_requested, event}}
      end
    end
  end

  defp list_comparison_review_events(organization_id, mission_id, dashboard_id) do
    DashboardLifecycleEventRow
    |> where(
      [event],
      event.organization_id == ^organization_id and event.mission_id == ^mission_id and
        event.dashboard_id == ^dashboard_id and
        event.event_type in ["comparison_review_requested", "comparison_review_resolved"]
    )
    |> order_by([event], asc: event.occurred_at, asc: event.dashboard_lifecycle_event_id)
    |> Repo.all()
    |> Enum.map(&DashboardLifecycleEventRow.to_domain/1)
  end

  defp comparison_review_request_overlaps?(%LifecycleEvent{} = event, incoming_placement_ids) do
    event
    |> comparison_review_request_placement_ids()
    |> Enum.any?(&(&1 in incoming_placement_ids))
  end

  defp reject_existing_comparison_review_resolution(
         organization_id,
         mission_id,
         dashboard_id,
         request_event_id
       ) do
    existing_resolution? =
      DashboardLifecycleEventRow
      |> where(
        [event],
        event.organization_id == ^organization_id and event.mission_id == ^mission_id and
          event.dashboard_id == ^dashboard_id and event.event_type == "comparison_review_resolved" and
          fragment(
            "(? ->> 'source_request_event_id' = ? OR ? -> 'value' ->> 'source_request_event_id' = ?)",
            event.payload,
            ^request_event_id,
            event.payload,
            ^request_event_id
          )
      )
      |> Repo.exists?()

    if existing_resolution? do
      {:error, :comparison_review_already_resolved}
    else
      :ok
    end
  end

  defp payload_value(payload, key) when is_map(payload) and is_binary(key) do
    Map.get(payload, key) || Map.get(payload, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(payload, key)
  end

  defp payload_value(_payload, _key), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""

  defp placement_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(_value), do: []
end
