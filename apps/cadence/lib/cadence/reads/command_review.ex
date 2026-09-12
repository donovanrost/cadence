defmodule Cadence.Reads.CommandReview do
  @moduledoc "Exact privileged command request semantics and bounded decision history."
  import Ecto.Query

  alias Cadence.Commanding.{
    CommandApprovalRow,
    CommandRequestRow
  }

  alias Cadence.Ids
  alias Cadence.Management.Commanding.RequestReview
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @fields ~w(command_request_id source_endpoint_ref mission_model_revision_id command_id command_name command_display_name lifecycle_state verification_state priority source_command_stage_id source_staged_command_item_id significance critical hazardous subsystem group_name preferred_uplink_service release_policy_hint apid service_type service_subtype)a

  def load(scope, mission_id, request_id, params \\ %{}) do
    with {:ok, fresh, mission} <- RequestReview.authorize(scope, mission_id),
         {:ok, _} <- Ids.path_segment(request_id),
         {:ok, cursor} <- cursor(params) do
      Repo.transaction(fn -> locked_snapshot(fresh, mission, request_id, cursor) end)
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp locked_snapshot(fresh, mission, request_id, cursor) do
    mission_id = mission.mission_id

    row =
      Repo.one(
        from(r in CommandRequestRow,
          where:
            r.organization_id == ^fresh.organization_id and r.mission_id == ^mission_id and
              r.command_request_id == ^request_id,
          lock: "FOR SHARE"
        )
      )

    if is_nil(row), do: Repo.rollback(:unavailable)
    request = CommandRequestRow.to_domain(row)

    data = %{
      "version" => 1,
      "context" => %{
        "organizationId" => fresh.organization_id,
        "missionId" => mission_id,
        "resourceId" => request_id
      },
      "mission_name" => mission.display_name,
      "actor_id" => fresh.user.user_id,
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "expected_review" => RequestReview.review_token(request),
      "request" => request_document(request),
      "can_decide" =>
        request.lifecycle_state == :approval_pending and
          request.requested_by["user_id"] != fresh.user.user_id,
      "query" => %{"after" => cursor || ""},
      "history" => history(fresh.organization_id, mission_id, request_id, cursor)
    }

    if byte_size(Jason.encode!(data)) <= 131_072, do: data, else: Repo.rollback(:unavailable)
  end

  defp actor(document) when is_map(document),
    do: Map.take(document, ~w(actor_kind user_id service_identity_id))

  defp actor(_), do: %{}

  defp request_document(request) do
    request
    |> Map.take(@fields)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.merge(%{
      "argument_values_json" => Jason.encode!(request.argument_values, pretty: true),
      "resolved_argument_values_json" =>
        Jason.encode!(request.resolved_argument_values, pretty: true),
      "opcode_json" => Jason.encode!(request.opcode),
      "requested_by" => actor(request.requested_by),
      "requested_at" => time(request.requested_at),
      "not_before" => time(request.not_before),
      "expires_at" => time(request.expires_at)
    })
  end

  defp time(nil), do: nil
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp cursor(params) when is_map(params) and map_size(params) <= 1 do
    case params do
      %{"after" => ""} ->
        {:ok, nil}

      %{"after" => value} ->
        if Ids.valid_identifier?(value), do: {:ok, value}, else: {:error, :invalid_query}

      empty when map_size(empty) == 0 ->
        {:ok, nil}

      _ ->
        {:error, :invalid_query}
    end
  end

  defp cursor(_), do: {:error, :invalid_query}

  defp history(org, mission, request, cursor) do
    query =
      from(row in CommandApprovalRow,
        where:
          row.organization_id == ^org and row.mission_id == ^mission and
            row.command_request_id == ^request,
        order_by: [asc: row.command_approval_id],
        limit: 26,
        select:
          map(row, [:command_approval_id, :decision, :decided_by_document, :decided_at, :reason])
      )

    query = if cursor, do: where(query, [row], row.command_approval_id > ^cursor), else: query
    rows = Repo.all(query)
    entries = Enum.take(rows, 25)

    %{
      "entries" => Enum.map(entries, &approval/1),
      "next_after" =>
        if(length(rows) > 25, do: List.last(entries).command_approval_id, else: nil),
      "limit" => 25
    }
  end

  defp approval(row),
    do: %{
      "id" => row.command_approval_id,
      "decision" => row.decision,
      "actor" => actor(JsonDocument.unwrap_value(row.decided_by_document)),
      "decided_at" => time(row.decided_at),
      "reason" => row.reason
    }
end
