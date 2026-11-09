defmodule CadenceWeb.Console.BookingResolutionController do
  @moduledoc """
  #53 from the plan side (U32): resolve a booking the provider hasn't confirmed past the window,
  named by plan and pass (`plan.unconfirmed.passes[].snapshot_id`). Contract:
  docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Contacts.BookingResolutions
  alias Cadence.Control.PlanConfirmation
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @actions %{"booked" => :booked, "not_booked" => :not_booked}

  def resolve(conn, %{"plan_id" => plan_id, "snapshot_id" => snapshot_id} = params) do
    scope = conn.assigns.current_scope
    mission_id = conn.assigns.current_mission.mission_id

    with {:ok, action} <- action(params["action"]),
         {:ok, item} <-
           PlanConfirmation.item(scope.organization_id, mission_id, plan_id, snapshot_id),
         {:ok, result} <-
           BookingResolutions.resolve(
             scope,
             mission_id,
             item.contact_plan_execution_item_id,
             action,
             Map.take(params, ~w(note provider_reference))
           ) do
      json(conn, %{data: ConfigJSON.encode(reply(result))})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp action(value) do
    case Map.fetch(@actions, value) do
      {:ok, action} -> {:ok, action}
      :error -> {:error, {:invalid, %{action: "must be booked or not_booked"}}}
    end
  end

  # `provider_answer` says what the provider answered when it settled the booking itself.
  defp reply(%{outcome: outcome, item: item, resolution: resolution}) do
    %{
      outcome: outcome,
      provider_answer:
        if(outcome == :provider_answered,
          do: if(item.lifecycle_state == :reserved, do: "booked", else: "not_booked")
        ),
      resolution: %{
        actor: actor(resolution.actor_document),
        at: resolution.inserted_at,
        note: resolution.note,
        provider_reference: resolution.provider_reference
      }
    }
  end

  defp actor(%{"kind" => kind} = actor), do: %{kind: kind, id: actor["id"], name: actor["name"]}
  defp actor(_actor), do: nil

  defp error(conn, {:invalid, details}), do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:booking_already_resolved, by}),
    do: Problem.respond(conn, :booking_already_resolved, %{actor: actor(by)})

  defp error(conn, reason)
       when reason in [:booking_not_found, :booking_not_unconfirmed, :forbidden],
       do: Problem.respond(conn, reason)

  defp error(conn, _reason), do: Problem.respond(conn, :booking_not_unconfirmed)
end
