defmodule Cadence.Control.Commanding.WorkspaceSubmission do
  @moduledoc "Direct workspace commands, admitted atomically from exact server previews."
  alias Cadence.Catalog.Command.Compatibility
  alias Cadence.Commanding.{Dispatcher, ProcessNamespace, RequestQueueStore, RequestValidation}
  alias Cadence.Management.Commanding
  alias Cadence.Management.Commanding.{ApprovedCommand, RequestAuthoring}
  alias Cadence.Platform.ScopedReadUpdates, as: ReadUpdates
  alias Cadence.Repo

  def preview(scope, mission, commands) when is_list(commands) and length(commands) in 1..25 do
    with true <- unique_targets?(commands),
         {:ok, fresh, _} <- RequestAuthoring.authorize(scope, mission),
         {:ok, requests} <- collect(commands, &RequestAuthoring.preview(scope, mission, &1)),
         held = %{actor_id: fresh.user.user_id, requests: requests},
         held = Map.put(held, :token, RequestValidation.authoring_digest(held)),
         {:ok, :current} <- with_current(held, fn -> {:ok, :current} end),
         {:ok, _} <- public_preview(held) do
      {:ok, held}
    else
      false -> {:error, :invalid_command_authoring_batch}
      error -> error
    end
  end

  def preview(_, _, _), do: {:error, :invalid_command_authoring_batch}

  def public_preview(held) do
    public = %{
      "token" => held.token,
      "actor_id" => held.actor_id,
      "requests" => Enum.map(held.requests, &RequestAuthoring.public_preview/1)
    }

    case Jason.encode(public) do
      {:ok, json} when byte_size(json) <= 524_288 -> {:ok, public}
      _ -> {:error, :command_preview_unavailable}
    end
  end

  def current?(held), do: with_current(held, fn -> {:ok, :current} end) == {:ok, :current}

  # held is exclusively server-owned state. Both tokens are consumed by the page session.
  def submit(scope, mission, write_token, held, input) do
    with :ok <- expected(held, write_token, input),
         {:ok, fresh, _} <- RequestAuthoring.authorize(scope, mission),
         true <- fresh.user.user_id == held.actor_id do
      result = Repo.transaction(fn -> persist_batch(scope, mission, held) end)

      result
      |> ReadUpdates.publish_result(:commanding_changed, fresh.organization_id, mission)
      |> dispatch(fresh.organization_id, mission)
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  defp persist_batch(scope, mission, held) do
    case with_current(held, fn ->
           collect(held.requests, &create_and_enqueue(scope, mission, held.token, &1))
         end) do
      {:ok, requests} -> receipt(held, requests)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def recover(scope, mission, held) do
    with {:ok, fresh, _} <- RequestAuthoring.authorize(scope, mission),
         true <- fresh.user.user_id == held.actor_id,
         {:ok, requests} <- collect(held.requests, &recover_request(scope, mission, held, &1)) do
      {:ok, receipt(held, requests)}
    else
      _ -> {:error, :unconfirmed}
    end
  end

  defp create_and_enqueue(scope, mission, token, authoring) do
    with {:ok, created} <-
           RequestAuthoring.create(scope, mission, authoring, %{
             "expected_preview" => authoring.token
           }) do
      if authoring.request.lifecycle_state == :approval_pending do
        {:ok, request_receipt(created, authoring, nil)}
      else
        enqueue(scope, mission, token, authoring, created)
      end
    end
  end

  defp enqueue(scope, mission, token, authoring, created) do
    request = authoring.request

    with {:ok, approved} <-
           Commanding.fetch_approved_command(
             request.organization_id,
             mission,
             request.command_request_id
           ),
         {:ok, %{queue_entry: queue}} <-
           RequestQueueStore.enqueue_request(
             request.organization_id,
             mission,
             request.command_request_id,
             request.requested_by,
             metadata: %{
               "workspace_preview" => token,
               "approved_content_sha256" => approved.content_sha256
             },
             before_enqueue: fn current ->
               with {:ok, _, _} <- RequestAuthoring.authorize(scope, mission),
                    true <-
                      current == request and ApprovedCommand.matches_request?(approved, current) do
                 :ok
               else
                 _ -> {:error, :command_authoring_preview_changed}
               end
             end
           ) do
      {:ok, request_receipt(created, authoring, queue)}
    end
  end

  defp recover_request(scope, mission, held, authoring) do
    with {:ok, created} <- RequestAuthoring.recover(scope, mission, authoring) do
      if authoring.request.lifecycle_state == :approval_pending do
        {:ok, request_receipt(created, authoring, nil)}
      else
        recover_queue(created, held, authoring)
      end
    end
  end

  defp recover_queue(created, held, authoring) do
    request = authoring.request

    case RequestQueueStore.list_queue_entries(request.organization_id, request.mission_id,
           command_request_id: request.command_request_id
         ) do
      [queue] ->
        if queue.metadata["workspace_preview"] == held.token and
             queue.enqueued_by == request.requested_by and
             queue.source_endpoint_ref == request.source_endpoint_ref and
             queue.priority == request.priority and queue.not_before == request.not_before and
             queue.expires_at == request.expires_at,
           do: {:ok, request_receipt(created, authoring, queue)},
           else: {:error, :unconfirmed}

      _ ->
        {:error, :unconfirmed}
    end
  end

  defp with_current(held, operation) do
    [first | _] = held.requests
    requests = Enum.map(held.requests, & &1.request)
    targets = Map.new(held.requests, &{&1.request.command_request_id, &1.expected_target})

    RequestValidation.with_authoring_requests(
      requests,
      first.expected_basis,
      targets,
      fn validated, _ ->
        fingerprints =
          Enum.map(validated, fn {request, state} ->
            Compatibility.fingerprint(state.snapshot.catalog, request.command_id)
          end)

        if Enum.map(validated, &elem(&1, 0)) == requests and
             Enum.all?(fingerprints, &match?({:ok, _}, &1)) and
             length(Enum.uniq(fingerprints)) == 1,
           do: operation.(),
           else: {:error, :command_authoring_preview_changed}
      end
    )
  end

  defp unique_targets?(commands) do
    Enum.all?(commands, &is_map/1) and
      length(Enum.uniq_by(commands, & &1["source_endpoint_ref"])) == length(commands) and
      length(Enum.uniq_by(commands, &{&1["command_id"], &1["expected_basis"]})) == 1
  end

  defp expected(held, write, %{"expected_write" => write, "expected_preview" => token} = input)
       when is_map(held) and map_size(input) == 2 do
    if held.token == token and
         token == RequestValidation.authoring_digest(Map.delete(held, :token)),
       do: :ok,
       else: {:error, :command_authoring_preview_changed}
  end

  defp expected(_, _, _), do: {:error, :command_authoring_preview_changed}

  defp collect(items, operation) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, results} ->
      case operation.(item) do
        {:ok, result} -> {:cont, {:ok, results ++ [result]}}
        error -> {:halt, error}
      end
    end)
  end

  defp request_receipt(created, authoring, queue),
    do: %{
      "request_id" => created["request_id"],
      "target_id" => authoring.request.source_endpoint_ref,
      "requested_at" => created["requested_at"],
      "state" => if(queue, do: "queued", else: "approval_pending"),
      "queue_id" => if(queue, do: queue.command_queue_entry_id)
    }

  defp receipt(held, requests),
    do: %{
      "operation" => "commands_submitted",
      "actor_id" => held.actor_id,
      "requests" => requests
    }

  # Dispatch and read notifications happen only after every request and queue entry commits.
  defp dispatch({:ok, receipt} = result, org, mission) do
    Enum.each(receipt["requests"], fn request ->
      if request["queue_id"],
        do: Dispatcher.kick_lane(ProcessNamespace.default(), org, mission, request["target_id"])
    end)

    result
  end

  defp dispatch(result, _, _), do: result
end
