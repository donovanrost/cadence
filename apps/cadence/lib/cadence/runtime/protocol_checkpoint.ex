defmodule Cadence.Runtime.ProtocolCheckpoint do
  @moduledoc "Versioned, data-only checkpoints. Installation never grants send authority."
  alias Cadence.Capabilities.ExecutionResult
  alias Cadence.Platform.ContentHash

  alias Cadence.Runtime.{
    CapabilityRegistry,
    SessionReadiness,
    TimerService,
    TransportRecords,
    TransportSession
  }

  alias Cadence.Runtime.ProtocolCheckpoint.Data

  def handle(:export, state, context), do: export(state, context)
  def handle(:latest, state, context), do: latest(state, context)
  def handle({:restore, id}, state, context) when is_binary(id), do: restore(state, id, context)

  def handle(_, state, _context),
    do: {{:error, :unsupported_protocol_checkpoint_operation}, state}

  def export(state, context) do
    with nil <- state.protocol_restoration,
         {:ok, state} <- TransportSession.ensure(state),
         {:ok, document} <- build(state, context),
         {:ok, checkpoint} <- TransportRecords.save_protocol_checkpoint(state, document) do
      {{:ok, checkpoint}, state}
    else
      %{} -> {{:error, :protocol_recovery_unqualified}, state}
      {:error, _} = error -> {error, state}
    end
  end

  def automatic(%{session_handle: nil}, _context), do: {:ok, nil}

  def automatic(%{protocol_restoration: restoration}, _context) when not is_nil(restoration),
    do: {:error, :protocol_recovery_unqualified}

  def automatic(%{extension_state: %{cop1_mode: :fop}} = state, context) do
    with {:ok, document} <- build(state, context), do: {:ok, {state, document}}
  end

  def automatic(_state, _context), do: {:ok, nil}

  defp build(%{persist_runtime_records?: false}, _context),
    do: {:error, :protocol_checkpoint_history_required}

  defp build(state, context) do
    with {:ok, review} <- review(state),
         {:ok, protocol} <-
           CapabilityRegistry.export_protocol_checkpoint(
             state.process_namespace.capability_registry,
             state.family_key,
             state.extension_state,
             context
           ),
         {:ok, timers} <- timer_intents(state, protocol) do
      {:ok,
       %{
         "schema_version" => 1,
         "scope" => scope(state, review),
         "origin" => %{
           "runtime_id" => state.send_runtime_id,
           "session_incarnation" => review.incarnation
         },
         "captured_at" => DateTime.to_iso8601(context.current_time),
         "clock_mode" => Atom.to_string(state.timer_service.clock.mode),
         "protocol" => protocol,
         "timers" => timers
       }}
    end
  end

  def restore(state, checkpoint_id, context) do
    with {:ok, state} <- TransportSession.ensure(state),
         :ok <- block_for_restoration(state) do
      blocked = %{
        state
        | timer_service: TimerService.cancel_all(state.timer_service),
          session_admission: nil
      }

      restore_blocked(blocked, checkpoint_id, context)
    else
      {:error, _} = error -> {error, state}
    end
  end

  defp block_for_restoration(state) do
    with {:ok, current} <- review(state) do
      installed_basis =
        if state.protocol_restoration, do: state.protocol_restoration.target_basis_sha256

      if current.status == :blocked and installed_basis == current.basis_sha256 do
        :ok
      else
        revoke_for_restoration(state)
      end
    end
  end

  defp revoke_for_restoration(state) do
    case SessionReadiness.block(state.session_handle, :protocol_restoration_required) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def latest(state, _context) do
    case TransportSession.ensure(state) do
      {:ok, attached} ->
        result =
          with {:ok, review} <- review(attached),
               {:ok, document} <- TransportRecords.load_protocol_checkpoint(attached, :latest),
               :ok <- validate_envelope(document, attached, review) do
            {:ok, document}
          end

        {result, attached}

      error ->
        {error, state}
    end
  end

  defp restore_blocked(state, id, context) do
    with {:ok, review} <- review(state),
         {:ok, document} <- TransportRecords.load_protocol_checkpoint(state, id),
         :ok <- validate_envelope(document, state, review),
         {:ok, %ExecutionResult{action_requests: [], records: []} = result} <-
           CapabilityRegistry.restore_protocol_checkpoint(
             state.process_namespace.capability_registry,
             state.family_key,
             document["protocol"],
             state.extension_state,
             context
           ),
         {:ok, timers} <- validate_timers(document["timers"], result.state),
         :ok <- current_session?(state, review),
         {:ok, installation} <-
           TransportRecords.record_protocol_restoration(state, document, review) do
      restoration = %{
        restoration_id: installation["restoration_id"],
        checkpoint_id: installation["checkpoint_id"],
        checkpoint_sha256: installation["checkpoint_sha256"],
        checkpoint_revision: installation["checkpoint_revision"],
        basis_sha256: installation["basis_sha256"],
        target_runtime_id: installation["target_runtime_id"],
        target_session_incarnation: installation["target_session_incarnation"],
        target_basis_sha256: installation["target_basis_sha256"],
        status: :installed_pending_reconciliation,
        timers:
          Enum.map(
            timers,
            &Map.put(&1, :expired?, DateTime.compare(&1.due_at, context.current_time) != :gt)
          )
      }

      {{:ok, restoration},
       %{
         state
         | extension_state: result.state,
           protocol_restoration: restoration,
           uplink_generation: nil
       }}
    else
      {:ok, %ExecutionResult{}} -> {{:error, :checkpoint_restoration_emitted_effects}, state}
      {:error, _} = error -> {error, state}
    end
  end

  defp current_session?(state, original) do
    with {:ok, current} <- review(state),
         true <- current.basis_sha256 == original.basis_sha256 do
      :ok
    else
      _ -> {:error, :protocol_restoration_session_changed}
    end
  end

  defp review(%{session_handle: nil}), do: {:error, :uplink_session_unavailable}
  defp review(state), do: SessionReadiness.review(state.session_handle)

  def scope(state, review) do
    %{
      "resource_id" => review.resource_id,
      "mission_id" => state.mission_id,
      "contact_id" => state.realized_contact_id,
      "path_id" => state.path_id,
      "family_key" => Atom.to_string(state.family_key),
      "binding_id" => state.capability_instance_id,
      "binding_set_id" => state.binding_set_id,
      "binding_set_version" => state.binding_set_version,
      "activation_id" => state.activation_id,
      "configuration_sha256" => ContentHash.term_sha256(state.configuration),
      "provider_configuration_sha256" => review.provider.configuration_sha256
    }
  end

  def seal(document), do: Map.put(document, "sha256", ContentHash.term_sha256(document))

  def valid_hash?(%{"sha256" => hash} = document),
    do: hash == ContentHash.term_sha256(Map.delete(document, "sha256"))

  def valid_hash?(_), do: false

  defp validate_envelope(document, state, review) do
    cond do
      document["schema_version"] != 1 ->
        {:error, :unsupported_protocol_checkpoint_version}

      not valid_hash?(document) ->
        {:error, :protocol_checkpoint_hash_mismatch}

      document["scope"] != scope(state, review) ->
        {:error, :protocol_checkpoint_scope_mismatch}

      document["clock_mode"] != Atom.to_string(state.timer_service.clock.mode) ->
        {:error, :protocol_checkpoint_clock_mismatch}

      not match?({:ok, _, 0}, DateTime.from_iso8601(document["captured_at"])) ->
        {:error, :invalid_protocol_checkpoint}

      checkpoint_future?(document, state) ->
        {:error, :protocol_checkpoint_from_future}

      true ->
        :ok
    end
  rescue
    _ -> {:error, :invalid_protocol_checkpoint}
  end

  defp checkpoint_future?(document, state) do
    {:ok, captured, 0} = DateTime.from_iso8601(document["captured_at"])
    DateTime.compare(captured, TimerService.current_time(state.timer_service)) == :gt
  end

  defp timer_intents(state, _protocol) do
    result =
      state.timer_service
      |> TimerService.snapshot()
      |> Enum.reduce_while({:ok, []}, fn timer, {:ok, acc} ->
        case Data.encode(timer.metadata) do
          {:ok, metadata} ->
            intent = %{
              "timer_key" => timer.timer_key,
              "due_at" => DateTime.to_iso8601(timer.due_at),
              "metadata" => metadata
            }

            {:cont, {:ok, acc ++ [intent]}}

          error ->
            {:halt, error}
        end
      end)

    with {:ok, timers} <- result,
         {:ok, _} <- validate_timers(timers, state.extension_state),
         do: {:ok, timers}
  end

  defp validate_timers(timers, %{cop1: fop}) when is_list(timers) do
    expected = if fop.timer_running, do: ["cop1:t1:#{fop.vcid}"], else: []

    if Enum.map(timers, & &1["timer_key"]) == expected do
      parsed =
        Enum.map(timers, fn timer ->
          {:ok, deadline, 0} = DateTime.from_iso8601(timer["due_at"])
          {:ok, metadata} = Data.decode(timer["metadata"])
          true = is_map(metadata)
          %{timer_key: timer["timer_key"], due_at: deadline, metadata: metadata}
        end)

      {:ok, parsed}
    else
      {:error, :protocol_checkpoint_timer_mismatch}
    end
  rescue
    _ -> {:error, :invalid_protocol_checkpoint_timer}
  end

  defp validate_timers(_, _), do: {:error, :invalid_protocol_checkpoint_timer}
end
