defmodule Cadence.Control.Commanding.QueueSubmission do
  @moduledoc "Finite human queue admission pinned to reviewed command content."
  alias Cadence.Commanding, as: CoreCommanding
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Control.Commanding
  alias Cadence.Ids
  alias Cadence.Management.Commanding, as: ManagementCommanding
  alias Cadence.Management.Commanding.{ApprovedCommand, RequestReview}

  @request_fields ~w(command_request_id source_endpoint_ref mission_model_revision_id command_id command_name command_display_name lifecycle_state verification_state priority source_command_stage_id source_staged_command_item_id significance critical hazardous subsystem group_name preferred_uplink_service release_policy_hint apid service_type service_subtype)a

  def load(scope, mission_id, request_id) do
    with {:ok, fresh, mission} <- RequestReview.authorize(scope, mission_id),
         {:ok, _} <- Ids.path_segment(request_id),
         {:ok, request} <-
           ManagementCommanding.fetch_command_request(
             fresh.organization_id,
             mission_id,
             request_id
           ),
         {:ok, queue} <- queue(fresh.organization_id, mission_id, request_id) do
      held = hold(fresh, request, queue)

      model = %{
        "version" => 1,
        "context" => %{
          "organizationId" => fresh.organization_id,
          "missionId" => mission_id,
          "resourceId" => request_id
        },
        "mission_name" => mission.display_name,
        "actor_id" => fresh.user.user_id,
        "observed_at" => time(DateTime.utc_now()),
        "request" => request_document(request),
        "target_name" =>
          Cadence.SourceEndpoints.display_names(fresh.organization_id, mission_id, [
            request.source_endpoint_ref
          ])
          |> Map.get(request.source_endpoint_ref),
        "queue" => queue_document(queue),
        "availability" => availability(request, queue, held)
      }

      if byte_size(Jason.encode!(%{model: model, preview: public_preview(held)})) <= 262_144,
        do: {:ok, %{model: model, held: held}},
        else: {:error, :unavailable}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  # held is server state from load/3, never decoded from a browser payload.
  def submit(scope, mission_id, held, %{"expected_queue" => expected} = input)
      when is_map(held) and map_size(input) == 1 do
    with {:ok, fresh, _} <- RequestReview.authorize(scope, mission_id),
         :ok <- held_scope(fresh, mission_id, held),
         true <- expected == held.token,
         {:ok, %{queue_entry: queued}} <-
           Commanding.enqueue(held.approved, held.actor,
             metadata: %{"operator_submission_id" => held.operation_id},
             before_enqueue: fn request -> authorize_insert(scope, mission_id, held, request) end
           ) do
      {:ok, receipt(queued, held)}
    else
      false -> {:error, :command_queue_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit(_, _, _, _), do: {:error, :command_queue_changed}

  def recover(scope, mission_id, held) when is_map(held) do
    with {:ok, fresh, _} <- RequestReview.authorize(scope, mission_id),
         :ok <- held_scope(fresh, mission_id, held),
         {:ok, queued} when not is_nil(queued) <-
           queue(fresh.organization_id, mission_id, held.approved.command_request_id),
         {:ok, request} <-
           ManagementCommanding.fetch_command_request(
             fresh.organization_id,
             mission_id,
             held.approved.command_request_id
           ),
         true <- ApprovedCommand.matches_request?(held.approved, request),
         true <- queued.enqueued_by == held.actor,
         true <- queued.metadata["operator_submission_id"] == held.operation_id,
         true <- queued.metadata["approved_content_sha256"] == held.approved.content_sha256,
         true <- same_queue_intent?(queued, held.approved) do
      {:ok, receipt(queued, held)}
    else
      _ -> {:error, :unconfirmed}
    end
  end

  def recover(_, _, _), do: {:error, :unconfirmed}

  def public_preview(nil), do: nil

  def public_preview(held) do
    approved = held.approved

    %{
      "token" => held.token,
      "operation_id" => held.operation_id,
      "actor_id" => held.actor["user_id"],
      "request" => request_document(held.request),
      "approval" => %{
        "id" => approved.command_approval_id,
        "basis_sha256" => approved.content_sha256,
        "actor" => actor(approved.approved_by),
        "decided_at" => time(approved.approved_at)
      }
    }
  end

  defp hold(fresh, %CommandRequest{lifecycle_state: state} = request, nil)
       when state in [:validated, :approved] do
    with true <- unexpired?(request),
         {:ok, approved} <-
           ManagementCommanding.fetch_approved_command(
             fresh.organization_id,
             request.mission_id,
             request.command_request_id
           ),
         true <- ApprovedCommand.matches_request?(approved, request) do
      %{
        token: Ecto.UUID.generate(),
        operation_id: Ids.new("queue_submission"),
        approved: approved,
        request: request,
        actor: %{"actor_kind" => "user", "user_id" => fresh.user.user_id},
        expected_review: RequestReview.review_token(request)
      }
    else
      _ -> nil
    end
  end

  defp hold(_, _, _), do: nil

  defp held_scope(fresh, mission, held) do
    if held.approved.organization_id == fresh.organization_id and
         held.approved.mission_id == mission and
         held.actor == %{"actor_kind" => "user", "user_id" => fresh.user.user_id},
       do: :ok,
       else: {:error, :unavailable}
  end

  defp authorize_insert(scope, mission, held, request) do
    with {:ok, fresh, _} <- RequestReview.authorize(scope, mission),
         :ok <- held_scope(fresh, mission, held),
         true <- RequestReview.review_token(request) == held.expected_review do
      :ok
    else
      false -> {:error, :command_queue_changed}
      _ -> {:error, :unavailable}
    end
  end

  defp queue(org, mission, request) do
    case CoreCommanding.list_command_queue_entries(org, mission, command_request_id: request) do
      [] -> {:ok, nil}
      [queued] -> {:ok, queued}
      _ -> {:error, :unavailable}
    end
  end

  defp unexpired?(%{expires_at: nil}), do: true
  defp unexpired?(request), do: DateTime.compare(request.expires_at, DateTime.utc_now()) == :gt
  defp availability(_, queue, _) when not is_nil(queue), do: "queued"
  defp availability(_, _, held) when not is_nil(held), do: "available"
  defp availability(%{lifecycle_state: :approval_pending}, _, _), do: "approval_required"
  defp availability(request, _, _), do: if(unexpired?(request), do: "closed", else: "expired")

  defp request_document(request) do
    request
    |> Map.take(@request_fields)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.merge(%{
      "requested_by" => actor(request.requested_by),
      "requested_at" => time(request.requested_at),
      "not_before" => time(request.not_before),
      "expires_at" => time(request.expires_at),
      "argument_values_json" => Jason.encode!(request.argument_values, pretty: true),
      "resolved_argument_values_json" =>
        Jason.encode!(request.resolved_argument_values, pretty: true),
      "opcode_json" => Jason.encode!(request.opcode)
    })
  end

  defp queue_document(nil), do: nil

  defp queue_document(queue) do
    %{
      "id" => queue.command_queue_entry_id,
      "request_id" => queue.command_request_id,
      "target_id" => queue.source_endpoint_ref,
      "lane" => queue.queue_lane_key,
      "sequence" => Integer.to_string(queue.queue_sequence),
      "priority" => queue.priority,
      "state" => to_string(queue.lifecycle_state),
      "enqueued_at" => time(queue.enqueued_at),
      "actor" => actor(queue.enqueued_by),
      "not_before" => time(queue.not_before),
      "expires_at" => time(queue.expires_at)
    }
  end

  defp same_queue_intent?(queue, approved) do
    queue.source_endpoint_ref == approved.source_endpoint_ref and
      queue.queue_lane_key == approved.source_endpoint_ref and
      queue.priority == approved.priority and queue.not_before == approved.not_before and
      queue.expires_at == approved.expires_at
  end

  defp receipt(queue, held),
    do: %{
      "operation_id" => held.operation_id,
      "queue_id" => queue.command_queue_entry_id,
      "request_id" => queue.command_request_id,
      "actor_id" => held.actor["user_id"],
      "enqueued_at" => time(queue.enqueued_at),
      "approved_content_sha256" => held.approved.content_sha256
    }

  defp actor(value) when is_map(value),
    do: Map.take(value, ~w(actor_kind user_id service_identity_id kind id display_name))

  defp actor(_), do: %{}
  defp time(nil), do: nil
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
