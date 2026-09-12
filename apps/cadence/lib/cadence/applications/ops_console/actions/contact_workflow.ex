defmodule Cadence.Applications.OpsConsole.Actions.ContactWorkflow do
  @moduledoc "Captured scheduling and provider-change commands using governed domain adapters."
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.{ContactPlanning, ProviderChangeDecisions}
  alias Cadence.Auth.Policy
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.Control.Contacts

  @schedule ~w(search reserve cancel)
  @decisions ~w(approve-provider-change reject-provider-change acknowledge-provider-change)
  @no_effect ~w(forbidden scope_mismatch malformed_input malformed_action_request unsupported_action
    invalid_reason invalid_provider_change_evidence stale_provider_change_evidence
    invalid_reservation_cancellation_evidence stale_reservation_cancellation_evidence
    provider_reservation_not_found opportunity_expired_or_unavailable opportunity_scope_mismatch
    route_changed provider_scheduling_route_not_ready invalid_search_window invalid_search_datetime)a

  def actions("schedule"), do: @schedule
  def actions("reservation"), do: @decisions
  def actions(_), do: []

  def execute(scope, mission, session, action, input) do
    with true <- action in actions(session.kind),
         :ok <- authorize(scope, mission, action),
         :ok <- captured(session, action, input) do
      scope
      |> dispatch(mission, session.kind, action, input)
      |> outcome(scope, mission, action)
      |> recover_cancellation(scope, mission, action, input)
    else
      {:error, :forbidden} -> {:rejected, ["forbidden"]}
      _ -> {:rejected, ["review_changed"]}
    end
  end

  defp recover_cancellation({:error, :unconfirmed}, scope, mission, "cancel", input) do
    id = input["reservation_evidence"]["reservation_id"]

    case ProviderReservations.fetch(scope.organization_id, mission, id) do
      {:ok, row}
      when row.lifecycle_state in [:canceling, :failed, :unknown, :rejected, :canceled] ->
        evidence = recovery(row, "cancel")

        case recover(scope, mission, evidence) do
          {:ok, result} -> {:ok, result}
          _ -> {:unconfirmed, wrap(scope, mission, "cancel", booking(row), "recorded"), evidence}
        end

      _ ->
        {:error, :unconfirmed}
    end
  end

  defp recover_cancellation(result, _, _, _, _), do: result

  def recover(scope, mission, %{reservation_id: id} = evidence) do
    with {:ok, row} <- ProviderReservations.fetch(scope.organization_id, mission, id),
         true <-
           row.provider_id == evidence.provider_id and
             row.provider_version == evidence.provider_version,
         true <- row.idempotency_key == evidence.idempotency_key,
         true <- row.provider_revision > 0 and is_binary(row.provider_contact_ref),
         true <- settled?(evidence.action, row.lifecycle_state) do
      {:ok, wrap(scope, mission, evidence.action, booking(row), "observed")}
    else
      _ -> {:error, :unconfirmed}
    end
  end

  def recover(_, _, _), do: {:error, :unconfirmed}

  defp settled?("cancel", state), do: state == :canceled

  defp settled?("reserve", state),
    do: state in [:pending, :confirmed, :active, :completed, :rejected, :canceled]

  defp authorize(scope, mission, action) do
    permission =
      cond do
        action == "cancel" -> :manage_missions
        action in @decisions -> :approve_provider_changes
        true -> :operate_mission
      end

    context =
      if permission == :manage_missions,
        do: %{organization_id: scope.organization_id},
        else: %{organization_id: scope.organization_id, mission_id: mission}

    if scope.mission_id in [nil, mission] and Policy.authorize(scope, permission, context) == :ok,
      do: :ok,
      else: {:error, :forbidden}
  end

  defp captured(session, "search", %{"contact_search" => form, "route_evidence" => evidence})
       when is_map(form) and is_map(evidence) do
    route =
      Enum.find(
        session.model["routes"]["entries"],
        &(&1["key"] == form["route_key"] and &1["spacecraft_id"] == form["spacecraft_id"])
      )

    if route && route["evidence"] == evidence, do: :ok, else: {:error, :review_changed}
  end

  defp captured(session, "reserve", %{"token" => token}) do
    opportunities = if session.search, do: session.search["opportunities"], else: []

    if token not in session.consumed and Enum.any?(opportunities, &(&1["token"] == token)),
      do: :ok,
      else: {:error, :review_changed}
  end

  defp captured(session, "cancel", %{"reservation_evidence" => evidence}) when is_map(evidence) do
    row =
      Enum.find(
        session.model["reservations"]["entries"],
        &(&1["id"] == evidence["reservation_id"])
      )

    expected =
      if row do
        Map.merge(session.model["context"], %{
          "contract_version" => 1,
          "reservation_id" => row["id"],
          "provider_revision" => row["provider_revision"],
          "lifecycle_state" => row["lifecycle_state"],
          "provider_contact_ref" => row["provider_contact_ref"]
        })
      end

    if expected && expected == evidence, do: :ok, else: {:error, :review_changed}
  end

  defp captured(%{kind: "reservation", model: model}, action, input) when action in @decisions do
    selected = model["selected"]

    expected =
      if selected do
        Map.merge(model["context"], %{
          "contract_version" => 1,
          "reservation_id" => model["reservation"]["id"],
          "change_id" => selected["id"],
          "provider_revision" => selected["provider_revision"],
          "proposal_hash" => selected["proposal_hash"]
        })
      end

    if (expected && input["change_evidence"] == expected) and
         input["provider_reservation_id"] == expected["reservation_id"],
       do: :ok,
       else: {:error, :review_changed}
  end

  defp captured(_, _, _), do: {:error, :review_changed}

  defp dispatch(scope, mission, "schedule", action, input) do
    ContactPlanning.execute(
      scope,
      HostContext.mission(mission),
      "contact_schedule",
      %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: action,
        params: input
      }
    )
  end

  defp dispatch(scope, mission, "reservation", action, input),
    do: ProviderChangeDecisions.decide(scope, mission, action, input)

  defp outcome({:ok, value}, scope, mission, action) when action in ["reserve", "cancel"] do
    if value["lifecycleState"] in ["requesting", "unknown", "failed", "canceling"] do
      case ProviderReservations.fetch(
             scope.organization_id,
             mission,
             value["providerReservationId"]
           ) do
        {:ok, row} ->
          outcome({:error, {:provider_reservation_not_confirmed, row}}, scope, mission, action)

        _ ->
          {:error, :unconfirmed}
      end
    else
      {:ok, wrap(scope, mission, action, value, "returned")}
    end
  end

  defp outcome({:ok, value}, scope, mission, action) when is_map(value),
    do: {:ok, wrap(scope, mission, action, value, "returned")}

  defp outcome({:error, {:provider_reservation_not_confirmed, row}}, scope, mission, action) do
    result = wrap(scope, mission, action, booking(row), "recorded")

    if row.lifecycle_state == :rejected and action == "reserve" do
      {:ok, result}
    else
      {:unconfirmed, result, recovery(row, action)}
    end
  end

  defp outcome({:error, reason}, _, _, _) when reason in @no_effect,
    do: {:rejected, ["review_changed"]}

  defp outcome(_, _, _, "search"), do: {:rejected, ["search_unavailable"]}
  defp outcome(_, _, _, _), do: {:error, :unconfirmed}

  defp recovery(row, action),
    do: %{
      reservation_id: row.provider_reservation_id,
      provider_id: row.provider_id,
      provider_version: row.provider_version,
      idempotency_key: row.idempotency_key,
      action: action
    }

  defp wrap(scope, mission, action, value, source),
    do: %{
      contract_version: 1,
      actor_id: scope.user.user_id,
      organization_id: scope.organization_id,
      mission_id: mission,
      action: action,
      source: source,
      value: value
    }

  defp booking(row) do
    scheduled =
      case Contacts.fetch_scheduled_contact(
             row.organization_id,
             row.mission_id,
             row.scheduled_contact_id
           ) do
        {:ok, contact} -> contact.scheduled_contact_id
        _ -> nil
      end

    %{
      "providerReservationId" => row.provider_reservation_id,
      "providerRevision" => row.provider_revision,
      "lifecycleState" => Atom.to_string(row.lifecycle_state),
      "scheduledContactId" => scheduled
    }
  end
end
