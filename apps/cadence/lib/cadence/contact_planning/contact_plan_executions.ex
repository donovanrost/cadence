defmodule Cadence.ContactPlanning.ContactPlanExecutions do
  @moduledoc "Restart-safe execution of approved Contact Plan selections."

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    ContactPlanExecutionItem,
    ContentHash,
    Planner
  }

  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Management.Contacts.ApprovedContactPlan

  alias Cadence.Contacts.{ProviderBooking, ProviderReservation, ProviderReservations}
  alias Cadence.Contacts.ProviderScheduling

  alias Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow

  alias Cadence.Repo

  @processable_states ~w(pending requesting)

  @doc false
  @spec accept(ApprovedContactPlan.t()) :: :ok | {:error, term()}
  def accept(%ApprovedContactPlan{} = approved_plan) do
    results =
      Enum.map(approved_plan.opportunity_snapshot_ids, fn snapshot_id ->
        idempotency_key =
          "cadence:contact-plan:" <>
            ContentHash.sha256(%{
              "plan_id" => approved_plan.contact_plan_id,
              "plan_version" => approved_plan.contact_plan_version,
              "snapshot_id" => snapshot_id
            })

        ContactPlanExecutionItem.new(%{
          organization_id: approved_plan.organization_id,
          mission_id: approved_plan.mission_id,
          contact_plan_id: approved_plan.contact_plan_id,
          contact_plan_version: approved_plan.contact_plan_version,
          contact_opportunity_snapshot_id: snapshot_id,
          idempotency_key: idempotency_key,
          lifecycle_state: :pending,
          attempt_count: 0,
          last_error_document: %{}
        })
        |> ContactPlanExecutionItemRow.changeset()
        |> Repo.insert(on_conflict: :nothing)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec execute(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, %{plan: struct(), items: [ContactPlanExecutionItem.t()]}} | {:error, term()}
  def execute(%Scope{} = current_scope, mission_id, plan_id, opts \\ [])
      when is_binary(mission_id) and is_binary(plan_id) and is_list(opts) do
    with :ok <- authorize_execution(current_scope, mission_id, opts),
         {:ok, plan} <- begin_execution(current_scope.organization_id, mission_id, plan_id, opts),
         items <-
           list(
             current_scope.organization_id,
             mission_id,
             plan.contact_plan_id,
             plan.approved_version
           ),
         _processed <- process_items(items, opts),
         {:ok, projected_plan, projected_items} <-
           project_plan(
             current_scope.organization_id,
             mission_id,
             plan.contact_plan_id,
             plan.approved_version,
             opts
           ) do
      {:ok, %{plan: projected_plan, items: projected_items}}
    end
  end

  @spec list(binary(), binary(), binary(), pos_integer()) :: [ContactPlanExecutionItem.t()]
  def list(organization_id, mission_id, plan_id, plan_version) do
    ContactPlanExecutionItemRow
    |> where(
      [item],
      item.organization_id == ^organization_id and item.mission_id == ^mission_id and
        item.contact_plan_id == ^plan_id and item.contact_plan_version == ^plan_version
    )
    |> order_by([item], asc: item.inserted_at, asc: item.contact_plan_execution_item_id)
    |> Repo.all()
    |> Enum.map(&ContactPlanExecutionItemRow.to_domain/1)
  end

  defp begin_execution(organization_id, mission_id, plan_id, opts) do
    ManagementContacts.start_execution_projection(organization_id, mission_id, plan_id, now(opts))
  end

  defp process_item(
         %{provider_reservation_id: reservation_id, lifecycle_state: state} = item,
         opts
       )
       when is_binary(reservation_id) and reservation_id != "" and
              state in [:pending, :requesting, :uncertain] do
    case ProviderReservations.fetch(
           item.organization_id,
           item.mission_id,
           reservation_id
         ) do
      {:ok, reservation} -> finish_with_reservation(item, reservation, opts)
      {:error, reason} -> finish_without_reservation(item, :failed, reason, opts)
    end
  end

  defp process_item(item, opts) do
    processable =
      @processable_states ++ if(Keyword.get(opts, :retry_failed, false), do: ["failed"], else: [])

    if Atom.to_string(item.lifecycle_state) in processable do
      with {:ok, claimed} <- claim_item(item, opts),
           {:ok, snapshot} <- fetch_snapshot(claimed),
           :ok <- unexpired(snapshot, now(opts)),
           {:ok, route} <- resolve_exact_route(snapshot, opts) do
        reserve(claimed, snapshot, route, opts)
      else
        {:error, reason} -> finish_without_reservation(item, :failed, reason, opts)
      end
    else
      {:ok, item}
    end
  end

  defp process_items(items, opts) do
    items
    |> Task.async_stream(
      &process_item(&1, opts),
      ordered: true,
      max_concurrency: Keyword.get(opts, :execution_concurrency, 1),
      timeout: :infinity
    )
    |> Enum.to_list()
  end

  defp claim_item(item, opts) do
    now = now(opts)

    Repo.transaction(fn ->
      row =
        ContactPlanExecutionItemRow
        |> where(
          [candidate],
          candidate.contact_plan_execution_item_id == ^item.contact_plan_execution_item_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one!()

      processable =
        @processable_states ++
          if(Keyword.get(opts, :retry_failed, false), do: ["failed"], else: [])

      if row.lifecycle_state in processable do
        row
        |> ContactPlanExecutionItemRow.transition_changeset(%{
          lifecycle_state: "requesting",
          provider_reservation_id: row.provider_reservation_id,
          attempt_count: row.attempt_count + 1,
          last_error_document: %{},
          started_at: row.started_at || now,
          completed_at: nil
        })
        |> Repo.update!()
        |> ContactPlanExecutionItemRow.to_domain()
      else
        Repo.rollback(:contact_plan_execution_item_not_processable)
      end
    end)
    |> normalize_transaction()
  end

  defp fetch_snapshot(item) do
    case ManagementContacts.fetch_opportunity_snapshot(
           item.organization_id,
           item.mission_id,
           item.contact_opportunity_snapshot_id
         ) do
      {:error, :contact_opportunity_snapshot_not_found} ->
        {:error, :contact_plan_execution_snapshot_not_found}

      result ->
        result
    end
  end

  defp unexpired(snapshot, now) do
    if DateTime.after?(snapshot.expires_at, now),
      do: :ok,
      else: {:error, :contact_plan_execution_opportunity_expired}
  end

  defp resolve_exact_route(snapshot, opts) do
    resolver =
      Keyword.get(opts, :resolve_route, &ProviderScheduling.resolve_ready_downlink_route/4)

    binding = snapshot.route_binding_document

    case resolver.(
           snapshot.organization_id,
           snapshot.mission_id,
           binding["spacecraft_id"],
           binding["route_key"]
         ) do
      {:ok, route} ->
        if Planner.route_binding(route) == binding,
          do: {:ok, route},
          else: {:error, :contact_plan_execution_route_changed}

      {:error, _reason} ->
        {:error, :contact_plan_execution_route_not_ready}

      _other ->
        {:error, :contact_plan_execution_route_resolution_malformed}
    end
  end

  defp reserve(item, snapshot, route, opts) do
    reserve_fun = Keyword.get(opts, :reserve, &ProviderBooking.reserve/5)
    attrs = booking_attrs(item, snapshot, route)

    result =
      reserve_fun.(
        item.organization_id,
        item.mission_id,
        route.provider_id,
        attrs,
        Keyword.get(opts, :provider_opts, [])
      )

    case result do
      {:ok, %{provider_reservation: %ProviderReservation{} = reservation}} ->
        finish_with_reservation(item, reservation, opts)

      {:error, {:provider_reservation_not_confirmed, %ProviderReservation{} = reservation}} ->
        finish_with_reservation(item, reservation, opts)

      {:error, reason} ->
        finish_without_reservation(item, :failed, reason, opts)

      _other ->
        finish_without_reservation(item, :failed, :malformed_provider_booking_result, opts)
    end
  end

  defp booking_attrs(item, snapshot, route) do
    opportunity = snapshot.normalized_opportunity_document

    %{
      "provider_version" => route.provider_version,
      "opportunity_ref" => snapshot.provider_opportunity_ref,
      "provider_spacecraft_ref" => route.provider_spacecraft_ref,
      "spacecraft_id" => route.spacecraft_id,
      "transport_id" => route.transport_id,
      "transport_version" => route.transport_version,
      "service_profile_ref" => route.service_profile_ref,
      "delivery_profile_ref" => route.delivery_profile_ref,
      "provider_profile_id" => route.provider_profile_id,
      "provider_profile_version" => route.provider_profile_version,
      "source_endpoint_refs" => [route.source_endpoint_id],
      "path_template_ids" => [route.path_template_id],
      "path_template_version" => route.path_template_version,
      "routing_rule_id" => route.routing_rule_id,
      "starts_at" => snapshot.starts_at,
      "ends_at" => snapshot.ends_at,
      "ground_station_ref" => opportunity["ground_station_ref"],
      "antenna_or_service_pool_ref" => opportunity["antenna_or_service_pool_ref"],
      "transport_display_name" =>
        Map.get(route, :transport_display_name, route.route_display_name),
      "service_display_name" => route.service_display_name,
      "delivery_display_name" => route.delivery_display_name,
      "delivery_operator_summary" =>
        Map.get(route, :delivery_operator_summary, route.delivery_display_name),
      "idempotency_key" => item.idempotency_key,
      "contact_requirement_id" => snapshot.contact_requirement_id,
      "contact_requirement_version" => snapshot.contact_requirement_version,
      "contact_plan_id" => item.contact_plan_id,
      "contact_plan_version" => item.contact_plan_version,
      "contact_opportunity_snapshot_id" => item.contact_opportunity_snapshot_id
    }
  end

  defp finish_with_reservation(item, reservation, opts) do
    case exact_reservation_binding(item, reservation) do
      :ok ->
        {state, error} = execution_outcome(reservation)
        finish_item(item, state, reservation.provider_reservation_id, error, opts)

      {:error, reason} ->
        finish_without_reservation(item, :failed, reason, opts)
    end
  end

  defp exact_reservation_binding(item, reservation) do
    if reservation.contact_plan_id == item.contact_plan_id and
         reservation.contact_plan_version == item.contact_plan_version and
         reservation.contact_opportunity_snapshot_id == item.contact_opportunity_snapshot_id and
         reservation.idempotency_key == item.idempotency_key,
       do: :ok,
       else: {:error, :contact_plan_execution_reservation_binding_mismatch}
  end

  defp execution_outcome(%ProviderReservation{lifecycle_state: state})
       when state in [:confirmed, :active, :completed],
       do: {:reserved, %{}}

  defp execution_outcome(%ProviderReservation{lifecycle_state: :rejected} = reservation),
    do: {:rejected, reservation.last_error_document}

  defp execution_outcome(%ProviderReservation{lifecycle_state: :failed} = reservation),
    do: {:failed, reservation.last_error_document}

  defp execution_outcome(%ProviderReservation{} = reservation),
    do: {:uncertain, reservation.last_error_document}

  defp finish_without_reservation(item, state, reason, opts) do
    finish_item(item, state, item.provider_reservation_id, safe_error(reason), opts)
  end

  defp finish_item(item, state, provider_reservation_id, error, opts) do
    now = now(opts)

    case Repo.get(ContactPlanExecutionItemRow, item.contact_plan_execution_item_id) do
      nil ->
        {:error, :contact_plan_execution_item_not_found}

      row ->
        row
        |> ContactPlanExecutionItemRow.transition_changeset(%{
          lifecycle_state: Atom.to_string(state),
          provider_reservation_id: provider_reservation_id,
          attempt_count: row.attempt_count,
          last_error_document: error,
          started_at: row.started_at || now,
          completed_at: if(state in [:reserved, :rejected, :failed], do: now, else: nil)
        })
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, ContactPlanExecutionItemRow.to_domain(updated)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp project_plan(organization_id, mission_id, plan_id, plan_version, opts) do
    items = list(organization_id, mission_id, plan_id, plan_version)
    state = projection_state(items)

    ManagementContacts.update_execution_projection(
      organization_id,
      mission_id,
      plan_id,
      plan_version,
      state,
      projection_reason(items),
      now(opts)
    )
    |> case do
      {:ok, plan} -> {:ok, plan, items}
      {:error, reason} -> {:error, reason}
    end
  end

  defp projection_state(items) do
    states = Enum.map(items, & &1.lifecycle_state)
    reserved_count = Enum.count(states, &(&1 == :reserved))

    cond do
      states != [] and reserved_count == length(states) -> :reserved
      reserved_count > 0 -> :partially_reserved
      states != [] and Enum.all?(states, &(&1 in [:rejected, :failed])) -> :failed
      true -> :executing
    end
  end

  defp projection_reason(items) do
    counts = items |> Enum.frequencies_by(& &1.lifecycle_state)

    counts
    |> Enum.sort_by(fn {state, _count} -> state end)
    |> Enum.map_join(", ", fn {state, count} -> "#{state}=#{count}" end)
    |> then(&"execution projection: #{&1}")
  end

  defp authorize_member(current_scope, mission_id) do
    Policy.authorize(current_scope, :operate_mission, %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize_execution(%Scope{actor_kind: :user} = scope, mission_id, _opts),
    do: authorize_member(scope, mission_id)

  defp authorize_execution(%Scope{actor_kind: :service} = scope, mission_id, opts) do
    grant_id = Keyword.get(opts, :automation_grant_id)
    evidence = Keyword.get(opts, :automation_evidence, %{})

    case ManagementContacts.authorize_automation(
           scope,
           mission_id,
           grant_id,
           :execute,
           evidence,
           opts
         ) do
      {:ok, _grant} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_error(reason) when is_atom(reason), do: %{"code" => Atom.to_string(reason)}
  defp safe_error({reason, _detail}) when is_atom(reason), do: %{"code" => Atom.to_string(reason)}
  defp safe_error(_reason), do: %{"code" => "provider_booking_failed"}

  defp normalize_transaction({:ok, result}), do: {:ok, result}
  defp normalize_transaction({:error, reason}), do: {:error, reason}

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
