defmodule Cadence.Runtime.TransportRecords.Send do
  @moduledoc """
  Write-ahead evidence for physical sends, stored in existing transport action records.

  A committed preparation is potentially sent, including when no later observation
  exists. Local writes are not remote acceptance. These records are never replayed
  automatically and prepared records have no command verification signal.
  """
  import Ecto.Query
  alias Ecto.Multi

  alias Cadence.ActionRequests.ProviderRequest
  alias Cadence.{Ids, Repo}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.{SessionReadiness, TransportActionRequest}
  alias Cadence.Runtime.TransportRecords.TransportActionRequestRow

  def prepare(state, actions, next_protocol_state) do
    if Enum.any?(actions, &match?(%ProviderRequest{}, &1)) do
      protect(fn -> prepare_sends(state, actions, next_protocol_state) end)
    else
      {:ok, actions}
    end
  end

  defp prepare_sends(state, actions, next_protocol_state) do
    with {:ok, review} <- SessionReadiness.review(state.session_handle) do
      Repo.transaction(fn ->
        ensure_ordinary_continuity(state, actions, review)

        Enum.map(actions, &prepare_action(state, next_protocol_state, review, &1))
      end)
    end
  end

  defp ensure_ordinary_continuity(state, actions, review) do
    if Enum.any?(actions, &match?(%ProviderRequest{recovery_exchange: nil}, &1)) do
      case clear?(review.resource_id, state.send_runtime_id) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp prepare_action(state, next_protocol_state, review, %ProviderRequest{} = request) do
    ensure_new_recovery_operation(request, review.resource_id)
    id = Ids.new("transport_send")

    record = %TransportActionRequest{
      action_request_id: id,
      mission_id: state.mission_id,
      realized_contact_id: state.realized_contact_id,
      path_id: state.path_id,
      capability_instance_id: state.capability_instance_id,
      family_key: state.family_key,
      activation_id: state.activation_id,
      binding_set_id: state.binding_set_id,
      binding_set_version: state.binding_set_version,
      partition_affinity: state.partition_key.affinity,
      partition_value: state.partition_key.value,
      command_release_attempt_id: request.command_release_attempt_id,
      command_request_id: request.command_request_id,
      source_endpoint_ref: request.source_endpoint_ref,
      command_name: request.command_name,
      action_kind: :provider_send_prepared,
      signal_phase: nil,
      requested_at: DateTime.utc_now(),
      request_document: %{
        request: request |> Map.from_struct() |> Map.drop([:session_permit, :preparation_id]),
        request_sha256: ProviderRequest.digest(request),
        session_basis: review,
        protocol_before: protocol_snapshot(state.extension_state),
        protocol_after: protocol_snapshot(next_protocol_state),
        frames:
          Enum.with_index(request.payloads_base64, fn bytes, index ->
            %{
              frame_id:
                ContentHash.term_sha256(
                  {review.resource_id, review.incarnation, request.command_release_attempt_id,
                   request.recovery_exchange, bytes}
                ),
              ordinal: index,
              bytes_base64: bytes
            }
          end)
      },
      metadata: %{
        resource_id: review.resource_id,
        incarnation: review.incarnation,
        send_status: "prepared",
        send_runtime_id: state.send_runtime_id,
        recovery_operation_id:
          if(request.recovery_exchange, do: request.recovery_exchange.operation_id)
      }
    }

    case Repo.insert(TransportActionRequestRow.changeset(record)) do
      {:ok, _} -> %{request | preparation_id: id}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp prepare_action(_state, _next, _review, other), do: other

  defp ensure_new_recovery_operation(%ProviderRequest{recovery_exchange: nil}, _resource), do: :ok

  defp ensure_new_recovery_operation(request, resource) do
    operation_id = request.recovery_exchange.operation_id

    if Repo.exists?(
         from(r in TransportActionRequestRow,
           where:
             r.action_kind == "provider_send_prepared" and
               fragment("? ->> 'resource_id' = ?", r.metadata, ^resource) and
               fragment("? ->> 'recovery_operation_id' = ?", r.metadata, ^operation_id)
         )
       ),
       do: Repo.rollback(:recovery_operation_already_prepared)
  end

  # External-term bytes preserve binaries, structs and integer counter keys exactly.
  # They are evidence, not an automatically deserialized restoration format.
  defp protocol_snapshot(state) do
    %{
      external_term_base64: state |> :erlang.term_to_binary() |> Base.encode64(),
      next_frame_seq: Map.get(state, :next_frame_seq)
    }
  end

  def begin_send(provider, request) do
    with {:ok, review} <- SessionReadiness.review(provider.session_handle) do
      begin_prepared_send(provider, request, review)
    end
  end

  defp begin_prepared_send(provider, request, review) do
    transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "prepared-send-reconciliation:" <> provider.session_resource
      ])

      row =
        Repo.one(
          from(r in TransportActionRequestRow,
            where: r.action_request_id == ^request.preparation_id,
            lock: "FOR UPDATE"
          )
        )

      if request.recovery_exchange == nil and audited?(provider.session_resource),
        do: Repo.rollback(:unresolved_transport_send)

      if row && row.reconciliation_evidence != %{},
        do: Repo.rollback(:invalid_send_preparation)

      unless valid_preparation?(row, provider, request, review),
        do: Repo.rollback(:invalid_send_preparation)

      update_status!(row, "sending", %{})
    end)
    |> status_result()
  end

  defp valid_preparation?(nil, _, _, _), do: false

  defp valid_preparation?(row, provider, request, review) do
    row.action_kind == "provider_send_prepared" and
      row.mission_id == provider.mission_id and
      row.realized_contact_id == provider.realized_contact_id and
      row.path_id == provider.path_id and
      row.metadata["send_status"] == "prepared" and
      row.metadata["resource_id"] == provider.session_resource and
      row.metadata["incarnation"] == provider.session_handle.incarnation and
      row.request_document["session_basis"]["basis_sha256"] == review.basis_sha256 and
      row.request_document["request_sha256"] == ProviderRequest.digest(request)
  end

  def finish_send(request, result) do
    transaction(fn ->
      row =
        Repo.one!(
          from(r in TransportActionRequestRow,
            where: r.action_request_id == ^request.preparation_id,
            lock: "FOR UPDATE"
          )
        )

      if row.metadata["send_status"] != "sending",
        do: Repo.rollback(:send_observation_conflict)

      status = if result == :ok, do: "local_write_completed", else: "unknown"
      update_status!(row, status, %{observation: inspect(result)})
    end)
    |> status_result()
  end

  def add_send_confirmations(multi, actions) do
    requests =
      for %TransportActionRequest{action_kind: :provider_request} = action <- actions,
          id = Map.get(action.request_document, :preparation_id),
          is_binary(id),
          do: %ProviderRequest{preparation_id: id}

    Multi.run(multi, :transport_send_confirmations, fn _repo, _changes ->
      case confirm(requests) do
        :ok -> {:ok, :confirmed}
        {:error, _} = error -> error
      end
    end)
  end

  def confirm(actions) do
    requests = Enum.filter(actions, &match?(%ProviderRequest{}, &1))

    if requests == [] do
      :ok
    else
      transaction(fn ->
        Enum.each(requests, &confirm_request/1)
      end)
      |> status_result()
    end
  end

  defp confirm_request(request) do
    row =
      Repo.one!(
        from(r in TransportActionRequestRow,
          where: r.action_request_id == ^request.preparation_id,
          lock: "FOR UPDATE"
        )
      )

    case row.metadata["send_status"] do
      "transport_committed" -> :ok
      "local_write_completed" -> update_status!(row, "transport_committed", %{})
      _ -> Repo.rollback(:send_observation_conflict)
    end
  end

  defp transaction(fun), do: protect(fn -> Repo.transaction(fun) end)

  defp update_status!(row, status, extra) do
    metadata =
      row.metadata
      |> Map.merge(JsonDocument.encode(extra))
      |> Map.merge(%{
        "send_status" => status,
        "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
      })

    row |> Ecto.Changeset.change(metadata: metadata) |> Repo.update!()
  end

  def review(resource) do
    protect(fn ->
      rows =
        from(r in TransportActionRequestRow,
          where:
            r.action_kind == "provider_send_prepared" and
              fragment("? ->> 'resource_id' = ?", r.metadata, ^resource),
          order_by: [desc: r.requested_at, desc: r.action_request_id],
          limit: 100
        )
        |> Repo.all()

      {:ok, Enum.map(rows, &TransportActionRequestRow.to_domain/1)}
    end)
  end

  def clear?(resource, runtime_id \\ nil) do
    protect(fn ->
      cond do
        unresolved?(resource) ->
          {:error, :unresolved_transport_send}

        runtime_id && restoration_required?(resource, runtime_id) ->
          {:error, :protocol_state_restore_required}

        true ->
          :ok
      end
    end)
  end

  defp restoration_required?(resource, runtime_id) do
    Repo.exists?(
      from(r in TransportActionRequestRow,
        where:
          r.action_kind == "provider_send_prepared" and
            fragment("? ->> 'resource_id' = ?", r.metadata, ^resource) and
            fragment("? ->> 'recovery_operation_id' IS NULL", r.metadata) and
            fragment("? ->> 'send_runtime_id' IS DISTINCT FROM ?", r.metadata, ^runtime_id)
      )
    )
  end

  defp audited?(resource) do
    Repo.exists?(
      from(r in TransportActionRequestRow,
        where:
          r.action_kind == "provider_send_prepared" and
            fragment("? ->> 'resource_id' = ?", r.metadata, ^resource) and
            fragment("? <> '{}'::jsonb", r.reconciliation_evidence)
      )
    )
  end

  defp unresolved?(resource) do
    Repo.exists?(
      from(r in TransportActionRequestRow,
        where:
          r.action_kind == "provider_send_prepared" and
            fragment("? ->> 'resource_id' = ?", r.metadata, ^resource) and
            (fragment("? ->> 'send_status' != 'transport_committed'", r.metadata) or
               fragment("? <> '{}'::jsonb", r.reconciliation_evidence))
      )
    )
  end

  defp status_result({:ok, _}), do: :ok
  defp status_result({:error, reason}), do: {:error, reason}

  defp protect(fun) do
    fun.()
  rescue
    _ -> {:error, :transport_send_persistence_unavailable}
  catch
    :exit, _ -> {:error, :transport_send_persistence_unavailable}
  end
end
