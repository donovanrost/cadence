defmodule Cadence.Runtime.Commands.TargetDispatcher do
  @moduledoc """
  Target-scoped GenServer for command dispatch and verification.

  One TargetDispatcher per target, managed by TargetPipeline supervisor.
  Handles command validation, encoding, routing, and verification for a single target.

  ## Command Lookup

  Commands are looked up via the target's definition_set_id, ensuring each target
  uses the correct command dictionary version.

  ## Responsibilities

  1. **Validation** - Validate arguments against Argument specs
  2. **Phase Checking** - Ensure command is allowed in current mission phase
  3. **Hazard Handling** - Require confirmation for hazardous commands
  4. **Encoding** - Encode command to binary format
  5. **Routing** - Find appropriate interface for target
  6. **Transmission** - Send through protocol chain and interface
  7. **Verification** - Monitor CVT for verification (if configured)
  8. **Logging** - Record all activity to command_logs table
  9. **Pause/Resume** - Control whether commands are sent to this target

  ## Example

      # Basic command dispatch
      {:ok, cmd_id} = TargetDispatcher.dispatch(mission_id, target_id, "SET_MODE", %{mode: 1})

      # Pause dispatch to target (queue still accepts commands)
      :ok = TargetDispatcher.pause(mission_id, target_id)

      # Resume dispatch
      :ok = TargetDispatcher.resume(mission_id, target_id)
  """

  use GenServer
  require Logger

  alias Cadence.Commands
  alias Cadence.Commands.{Encoder, VerificationRunner}
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Interfaces
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Recordings

  alias Cadence.Recordings.Recordables.{
    CommandDispatched,
    CommandSent,
    CommandVerificationFailed,
    CommandVerified
  }

  alias Cadence.Repo
  alias Cadence.Runtime.Commands.{MetaCommandCache, TargetQueue}
  alias Cadence.Telemetry.ProtocolChain

  @confirmation_timeout_ms 60_000
  @default_dispatch_timeout_ms 30_000
  @queue_check_interval_ms 100

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :target_id,
      :target,
      :mission,
      # Dispatch task supervision
      :dispatch_task,
      :dispatch_timeout_ref,
      :executing_entry_id,
      # Interface tracking
      :write_interface_id,
      # State flags
      paused: false,
      executing: false,
      interface_connected: true,
      pending_confirmations: %{},
      pending_verifications: %{},
      command_counter: 0
    ]
  end

  defmodule ConfirmationRequest do
    @moduledoc false
    defstruct [
      :token,
      :command_name,
      :params,
      :opts,
      :hazard_description,
      :expires_at
    ]
  end

  ## Client API

  @doc """
  Starts dispatcher for a target.

  Requires:
  - `mission: mission_entity`
  - `target: target_entity`
  """
  def start_link(opts) do
    {mission, target} = extract_mission_and_target(opts)
    GenServer.start_link(__MODULE__, {mission, target}, name: via_tuple(mission.id, target.id))
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(mission_id, target_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:target_dispatcher, mission_id, target_id}}}
  end

  @doc """
  Returns the PID of a dispatcher by mission_id and target_id.
  """
  def whereis(mission_id, target_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:target_dispatcher, mission_id, target_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Pauses command dispatch to this target.

  When paused, the dispatcher will not send commands. Commands can still be
  enqueued via TargetQueue, they just won't be dispatched until resumed.
  """
  def pause(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :pause)
  end

  @doc """
  Resumes command dispatch to this target.
  """
  def resume(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :resume)
  end

  @doc """
  Returns whether this dispatcher is paused.
  """
  def paused?(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :paused?)
  end

  @doc """
  Dispatches a command to this target.

  ## Options

  - `:interface_id` - Specific interface to use (optional)
  - `:user_id` - User performing the action (for audit)
  - `:skip_verification` - Don't auto-verify even if configured
  - `:skip_hazardous_check` - Bypass hazardous confirmation (dangerous!)

  ## Returns

  - `{:ok, command_log_id}` - Command sent successfully
  - `{:error, :paused}` - Dispatcher is paused
  - `{:error, :requires_confirmation, %{token: ..., hazard_description: ...}}` - Hazardous command
  - `{:error, :validation_failed, errors}` - Argument validation failed
  - `{:error, :not_allowed_in_phase, current_phase}` - Phase restriction
  - `{:error, :unknown_command}` - Command not found
  - `{:error, :no_interface}` - No write interface for target
  - `{:error, :interface_disconnected}` - Interface not connected
  - `{:error, :encoding_failed, reason}` - Binary encoding failed
  - `{:error, :send_failed, reason}` - Transmission failed
  """
  def dispatch(mission_id, target_id, command_name, params, opts \\ []) do
    GenServer.call(via_tuple(mission_id, target_id), {:dispatch, command_name, params, opts})
  end

  @doc """
  Confirms and dispatches a hazardous command using a confirmation token.
  """
  def confirm_dispatch(mission_id, target_id, token) do
    GenServer.call(via_tuple(mission_id, target_id), {:confirm_dispatch, token})
  end

  @doc """
  Cancels a pending verification.
  """
  def cancel_verification(mission_id, target_id, command_log_id) do
    GenServer.cast(via_tuple(mission_id, target_id), {:cancel_verification, command_log_id})
  end

  @doc """
  Gets the status of a pending verification.
  """
  def verification_status(mission_id, target_id, command_log_id) do
    GenServer.call(via_tuple(mission_id, target_id), {:verification_status, command_log_id})
  end

  @doc """
  Gets dispatcher status including pause state.
  """
  def status(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :status)
  end

  ## Server Callbacks

  @impl true
  def init({%Mission{} = mission, %Target{} = target}) do
    Logger.info(
      "Starting TargetDispatcher for mission_id=#{mission.id}, target=#{target.identifier} (#{target.id})"
    )

    # Subscribe to interface connection events for this mission
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:events")

    # Look up the write interface for this target (if any)
    # This is the only DB call needed - interfaces may change independently
    {write_interface_id, interface_connected} =
      case Interfaces.list_interfaces_for_target(target, direction: "write") do
        [interface | _] -> {interface.id, true}
        [] -> {nil, true}
      end

    state = %State{
      mission_id: mission.id,
      target_id: target.id,
      target: target,
      mission: mission,
      write_interface_id: write_interface_id,
      interface_connected: interface_connected
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    Logger.info(
      "Pausing TargetDispatcher for mission_id=#{state.mission_id}, target_id=#{state.target_id}"
    )

    # Notify queue of paused state change (async to avoid deadlock)
    TargetQueue.set_dispatcher_paused(state.mission_id, state.target_id, true)

    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, state) do
    Logger.info(
      "Resuming TargetDispatcher for mission_id=#{state.mission_id}, target_id=#{state.target_id}"
    )

    # Notify queue of paused state change (async to avoid deadlock)
    TargetQueue.set_dispatcher_paused(state.mission_id, state.target_id, false)

    {:reply, :ok, %{state | paused: false}}
  end

  def handle_call(:paused?, _from, state) do
    {:reply, state.paused, state}
  end

  def handle_call({:dispatch, _command_name, _params, _opts}, _from, %{paused: true} = state) do
    {:reply, {:error, :paused}, state}
  end

  def handle_call({:dispatch, command_name, params, opts}, _from, state) do
    entry = %{id: nil, command_name: command_name, parameters: params}

    case do_dispatch(entry, opts, state) do
      {:ok, command_log_id, new_state} ->
        {:reply, {:ok, command_log_id}, new_state}

      {:requires_confirmation, confirmation_info, new_state} ->
        {:reply, {:error, :requires_confirmation, confirmation_info}, new_state}

      {:error, _} = error ->
        {:reply, error, state}

      {:error, _, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:confirm_dispatch, token}, _from, state) do
    case Map.get(state.pending_confirmations, token) do
      nil ->
        {:reply, {:error, :invalid_token}, state}

      %ConfirmationRequest{} = request ->
        handle_confirmation_request(request, token, state)
    end
  end

  def handle_call({:verification_status, command_log_id}, _from, state) do
    status =
      case Map.get(state.pending_verifications, command_log_id) do
        nil -> :not_found
        verification -> {:pending, verification}
      end

    {:reply, status, state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      mission_id: state.mission_id,
      target_id: state.target_id,
      paused: state.paused,
      executing: state.executing,
      interface_connected: state.interface_connected,
      write_interface_id: state.write_interface_id,
      pending_confirmations: map_size(state.pending_confirmations),
      pending_verifications: map_size(state.pending_verifications),
      command_counter: state.command_counter
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:cancel_verification, command_log_id}, state) do
    case Map.get(state.pending_verifications, command_log_id) do
      nil ->
        {:noreply, state}

      %{timeout_ref: ref} ->
        Process.cancel_timer(ref)

        new_state = %{
          state
          | pending_verifications: Map.delete(state.pending_verifications, command_log_id)
        }

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:verification_timeout, aggregate_id}, state) do
    # Simple verification timeout
    case Map.get(state.pending_verifications, aggregate_id) do
      nil ->
        {:noreply, state}

      %{type: :multi_stage} ->
        # Multi-stage uses its own timeout message
        {:noreply, state}

      verification ->
        Logger.warning("Simple command verification timeout for aggregate_id=#{aggregate_id}")

        # Record verification failed event
        record_command_verification_failed(state, aggregate_id, verification.recording_id, %{
          error_reason: "Verification timeout"
        })

        new_state = %{
          state
          | pending_verifications: Map.delete(state.pending_verifications, aggregate_id)
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:verification_stage_timeout, aggregate_id, stage}, state) do
    # Multi-stage verification timeout
    case Map.get(state.pending_verifications, aggregate_id) do
      nil ->
        {:noreply, state}

      %{type: :multi_stage, runner: runner} = verification ->
        handle_stage_timeout(aggregate_id, stage, verification, runner, state)

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:telemetry_update, target_id, packet_name, item_name, telemetry_value},
        %{target_id: target_id} = state
      ) do
    new_state =
      Enum.reduce(state.pending_verifications, state, fn {aggregate_id, verification}, acc ->
        apply_verification_update(
          acc,
          aggregate_id,
          verification,
          packet_name,
          item_name,
          telemetry_value.value
        )
      end)

    {:noreply, new_state}
  end

  def handle_info(
        {:telemetry_update, _target_id, _packet_name, _item_name, _telemetry_value},
        state
      ) do
    {:noreply, state}
  end

  # Queue processing - triggered by TargetQueue when commands are available
  def handle_info(:check_queue, %{paused: true} = state) do
    {:noreply, state}
  end

  def handle_info(:check_queue, %{interface_connected: false} = state) do
    # Interface has no clients - wait for connection before processing
    {:noreply, state}
  end

  def handle_info(:check_queue, %{executing: true} = state) do
    # Already executing a command, will check again when done
    {:noreply, state}
  end

  def handle_info(:check_queue, state) do
    case TargetQueue.next(state.mission_id, state.target_id) do
      nil ->
        # No commands ready
        {:noreply, state}

      entry ->
        # Got a command - execute it
        new_state = process_queue_entry(entry, state)
        {:noreply, new_state}
    end
  end

  # Task.async completion - normal result
  def handle_info({ref, result}, %{dispatch_task: %Task{ref: ref}} = state) do
    # Clean up the monitor
    Process.demonitor(ref, [:flush])

    # Cancel the timeout timer
    if state.dispatch_timeout_ref do
      Process.cancel_timer(state.dispatch_timeout_ref)
    end

    # Report result back to queue
    TargetQueue.complete(state.mission_id, state.target_id, state.executing_entry_id, result)

    # Check if we lost connection - don't immediately retry
    interface_connected =
      case result do
        {:error, :send_failed, :no_clients_connected} -> false
        {:error, :interface_not_running} -> false
        _ -> state.interface_connected
      end

    # Only check for more work if interface is still connected
    if interface_connected do
      Process.send_after(self(), :check_queue, @queue_check_interval_ms)
    end

    {:noreply,
     %{
       state
       | executing: false,
         dispatch_task: nil,
         dispatch_timeout_ref: nil,
         executing_entry_id: nil,
         interface_connected: interface_connected
     }}
  end

  # Task.async crash - the task process died
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{dispatch_task: %Task{ref: ref}} = state) do
    Logger.error(
      "Command dispatch task crashed for entry_id=#{state.executing_entry_id}: #{inspect(reason)}"
    )

    # Cancel the timeout timer
    if state.dispatch_timeout_ref do
      Process.cancel_timer(state.dispatch_timeout_ref)
    end

    # Report failure to queue
    TargetQueue.complete(
      state.mission_id,
      state.target_id,
      state.executing_entry_id,
      {:error, :task_crashed, inspect(reason)}
    )

    # Check for more work after a brief delay
    Process.send_after(self(), :check_queue, @queue_check_interval_ms)

    {:noreply,
     %{
       state
       | executing: false,
         dispatch_task: nil,
         dispatch_timeout_ref: nil,
         executing_entry_id: nil
     }}
  end

  # Dispatch timeout - task is taking too long
  def handle_info(:dispatch_timeout, %{executing: true, dispatch_task: task} = state)
      when not is_nil(task) do
    Logger.warning(
      "Command dispatch timeout for entry_id=#{state.executing_entry_id}, shutting down task"
    )

    # Gracefully shut down the task (gives it 5 seconds to finish)
    Task.shutdown(task, 5_000)

    # Report timeout to queue
    TargetQueue.complete(
      state.mission_id,
      state.target_id,
      state.executing_entry_id,
      {:error, :dispatch_timeout}
    )

    # Check for more work after a brief delay
    Process.send_after(self(), :check_queue, @queue_check_interval_ms)

    {:noreply,
     %{
       state
       | executing: false,
         dispatch_task: nil,
         dispatch_timeout_ref: nil,
         executing_entry_id: nil
     }}
  end

  # Stale dispatch timeout (already finished) - ignore
  def handle_info(:dispatch_timeout, state) do
    {:noreply, state}
  end

  # Interface connection events - update connection state
  def handle_info(
        {:interface_connection_event, %InterfaceConnectionEvent{} = event},
        state
      ) do
    # Only handle events for our write interface
    if event.interface_id == state.write_interface_id do
      case event.new_state do
        :connected ->
          Logger.info(
            "Interface #{event.interface_id} connected - resuming command dispatch for target #{state.target_id}"
          )

          # Trigger queue check now that we're connected
          send(self(), :check_queue)
          {:noreply, %{state | interface_connected: true}}

        :disconnected ->
          Logger.info(
            "Interface #{event.interface_id} disconnected - pausing command dispatch for target #{state.target_id}"
          )

          {:noreply, %{state | interface_connected: false}}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  # Confirmation request helpers (grouped separately from GenServer callbacks)
  defp handle_confirmation_request(request, token, state) do
    if confirmation_expired?(request) do
      {:reply, {:error, :token_expired}, drop_confirmation(state, token)}
    else
      dispatch_confirmed_request(request, token, state)
    end
  end

  defp confirmation_expired?(%ConfirmationRequest{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp drop_confirmation(state, token) do
    %{state | pending_confirmations: Map.delete(state.pending_confirmations, token)}
  end

  defp dispatch_confirmed_request(request, token, state) do
    opts = Keyword.put(request.opts, :skip_hazardous_check, true)
    state_without_confirmation = drop_confirmation(state, token)

    entry = %{
      id: nil,
      command_name: request.command_name,
      parameters: request.params
    }

    case do_dispatch(entry, opts, state_without_confirmation) do
      {:ok, command_log_id, new_state} ->
        {:reply, {:ok, command_log_id}, new_state}

      {:error, _} = error ->
        {:reply, error, state_without_confirmation}

      {:error, _, _} = error ->
        {:reply, error, state_without_confirmation}
    end
  end

  defp handle_stage_timeout(aggregate_id, stage, verification, runner, state) do
    if VerificationRunner.current_stage(runner) == stage do
      handle_timeout_action(
        VerificationRunner.handle_timeout(runner),
        aggregate_id,
        stage,
        verification,
        state
      )
    else
      {:noreply, state}
    end
  end

  defp handle_timeout_action(
         {:continue, updated_runner},
         aggregate_id,
         _stage,
         verification,
         state
       ) do
    advance_multi_stage(
      VerificationRunner.start_current_stage(updated_runner),
      aggregate_id,
      verification,
      state
    )
  end

  defp handle_timeout_action(
         {:retry, updated_runner},
         aggregate_id,
         _stage,
         verification,
         state
       ) do
    runner_with_timeout = VerificationRunner.start_timeout(updated_runner, self())
    updated_verification = %{verification | runner: runner_with_timeout}

    new_state = %{
      state
      | pending_verifications:
          Map.put(state.pending_verifications, aggregate_id, updated_verification)
    }

    {:noreply, new_state}
  end

  defp handle_timeout_action(
         {:abort, _runner},
         aggregate_id,
         stage,
         verification,
         state
       ) do
    Logger.warning(
      "Multi-stage verification aborted for aggregate_id=#{aggregate_id}, stage=#{stage}"
    )

    record_command_verification_failed(
      state,
      aggregate_id,
      verification.recording_id,
      %{
        error_reason: "Verification stage #{stage} timeout"
      }
    )

    new_state = %{
      state
      | pending_verifications: Map.delete(state.pending_verifications, aggregate_id)
    }

    {:noreply, new_state}
  end

  defp advance_multi_stage({:ok, runner_with_stage}, aggregate_id, verification, state) do
    runner_with_timeout = VerificationRunner.start_timeout(runner_with_stage, self())

    Logger.info(
      "Advancing to verification stage #{VerificationRunner.current_stage(runner_with_timeout)} " <>
        "for aggregate_id=#{aggregate_id}"
    )

    updated_verification = %{verification | runner: runner_with_timeout}

    new_state = %{
      state
      | pending_verifications:
          Map.put(state.pending_verifications, aggregate_id, updated_verification)
    }

    {:noreply, new_state}
  end

  defp advance_multi_stage({:complete, final_runner}, aggregate_id, verification, state) do
    new_state =
      complete_multi_stage_verification(
        state,
        aggregate_id,
        verification,
        final_runner
      )

    {:noreply, new_state}
  end

  defp apply_verification_update(
         acc,
         aggregate_id,
         %{type: :simple, item: item} = verification,
         packet_name,
         item_name,
         value
       ) do
    if item == "#{packet_name}.#{item_name}" do
      check_simple_verification(acc, aggregate_id, verification, value)
    else
      acc
    end
  end

  defp apply_verification_update(
         acc,
         aggregate_id,
         %{type: :multi_stage, runner: runner} = verification,
         packet_name,
         item_name,
         value
       ) do
    handle_multi_stage_update(
      acc,
      aggregate_id,
      verification,
      runner,
      packet_name,
      item_name,
      value
    )
  end

  defp apply_verification_update(
         acc,
         aggregate_id,
         %{item: item} = legacy_verification,
         packet_name,
         item_name,
         value
       ) do
    if item == "#{packet_name}.#{item_name}" do
      check_simple_verification(acc, aggregate_id, legacy_verification, value)
    else
      acc
    end
  end

  defp process_queue_entry(entry, state) do
    # Mark as executing in queue
    {:ok, _} = TargetQueue.mark_executing(state.mission_id, state.target_id, entry.id)

    # Execute asynchronously with Task.async for proper monitoring
    task =
      Task.async(fn ->
        # Convert stored opts back to keyword list
        opts =
          entry.dispatch_opts
          |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
          |> Keyword.put(:user_id, entry.user_id)

        result = do_dispatch(entry, opts, state)

        # Normalize result for queue
        case result do
          {:ok, %{aggregate_id: _, recording_id: _} = info, _new_state} -> {:ok, info}
          {:requires_confirmation, info, _new_state} -> {:error, :requires_confirmation, info}
          error -> error
        end
      end)

    # Start dispatch timeout timer
    dispatch_timeout = get_dispatch_timeout(state.target)
    timeout_ref = Process.send_after(self(), :dispatch_timeout, dispatch_timeout)

    %{
      state
      | executing: true,
        dispatch_task: task,
        dispatch_timeout_ref: timeout_ref,
        executing_entry_id: entry.id
    }
  end

  defp get_dispatch_timeout(target) do
    # Check target config for custom timeout, fall back to default
    case get_in(target.config, ["dispatch_timeout_ms"]) do
      nil -> @default_dispatch_timeout_ms
      timeout when is_integer(timeout) -> timeout
      _ -> @default_dispatch_timeout_ms
    end
  end

  defp do_dispatch(entry, opts, state) do
    # Use target from state - already loaded with definition_set
    target = state.target
    interface_id = Keyword.get(opts, :interface_id)

    Logger.info(
      "[DISPATCH] command_name=#{inspect(entry.command_name)}, " <>
        "mission_id=#{inspect(state.mission_id)}, target_id=#{target.id}, " <>
        "definition_set_id=#{inspect(target.definition_set_id)}"
    )

    with {:ok, command} <- get_command(state, target, entry.command_name),
         :ok <- check_phase_restriction(command, state.mission),
         :ok <- check_hazardous(command, entry.parameters, opts, state),
         :ok <- validate_args(command, entry.parameters),
         {:ok, encoded} <- encode_command(command, entry.parameters),
         {:ok, interface} <- get_interface(target, opts),
         {:ok, framed} <- process_protocol_chain(interface, encoded),
         {:ok, cmd_info} <-
           create_command_recording(state, command, target, entry.parameters, encoded, opts),
         :ok <- send_to_interface(interface, framed) do
      if entry.id do
        TargetQueue.attach_command_log(
          state.mission_id,
          state.target_id,
          entry.id,
          cmd_info.aggregate_id
        )
      end

      # Record command sent event
      record_command_sent(
        state,
        cmd_info.aggregate_id,
        cmd_info.recording_id,
        interface_id || interface.id
      )

      # Start verification if configured (using verifiers association)
      new_state =
        if Keyword.get(opts, :skip_verification, false) do
          state
        else
          start_verification(state, cmd_info, command, target)
        end

      {:ok, %{aggregate_id: cmd_info.aggregate_id, recording_id: cmd_info.recording_id},
       new_state}
    else
      {:error, :requires_confirmation, _} ->
        # Handle hazardous command - store confirmation request and return info
        create_hazardous_confirmation(entry.command_name, entry.parameters, opts, state)

      {:error, _} = error ->
        error

      {:error, _, _} = error ->
        error
    end
  end

  # Look up command using the MetaCommandCache for O(1) lookup.
  # Falls back to database query if cache is not available (e.g., during startup race).
  defp get_command(state, target, command_name) do
    definition_set_id = target.definition_set_id

    Logger.debug(
      "[GET_COMMAND] Looking up command_name=#{inspect(command_name)} " <>
        "for definition_set_id=#{inspect(definition_set_id)}"
    )

    # Try cache first (O(1) ETS lookup)
    case MetaCommandCache.get_by_name(state.mission_id, definition_set_id, command_name) do
      {:ok, command} ->
        Logger.debug("[GET_COMMAND] FOUND in cache - command id=#{command.id}")
        {:ok, command}

      {:error, reason} when reason in [:not_found, :cache_not_available] ->
        # Cache miss or not running - fall back to DB query
        if reason == :cache_not_available do
          Logger.debug("[GET_COMMAND] Cache not available, falling back to database")
        else
          Logger.debug("[GET_COMMAND] Cache miss, falling back to database")
        end

        case Commands.get_meta_command(definition_set_id, command_name) do
          nil ->
            Logger.warning(
              "[GET_COMMAND] NOT FOUND - definition_set_id=#{inspect(definition_set_id)}, " <>
                "command_name=#{inspect(command_name)}"
            )

            {:error, :unknown_command}

          command ->
            Logger.debug("[GET_COMMAND] FOUND in database - command id=#{command.id}")
            # Preload associations since they're not in cache
            command = Repo.preload(command, [:arguments, :verifiers, :transmission_constraints])
            {:ok, command}
        end
    end
  end

  defp check_phase_restriction(%MetaCommand{} = command, mission) do
    if MetaCommand.allowed_in_phase?(command, mission.phase) do
      :ok
    else
      {:error, :not_allowed_in_phase, mission.phase}
    end
  end

  defp check_hazardous(command, _params, opts, _state) do
    skip_check = Keyword.get(opts, :skip_hazardous_check, false)

    if not skip_check and MetaCommand.requires_confirmation?(command) do
      {:error, :requires_confirmation, command.hazard_description}
    else
      :ok
    end
  end

  defp validate_args(command, params) do
    case Commands.validate_arguments(command, params) do
      :ok -> :ok
      {:error, errors} -> {:error, :validation_failed, errors}
    end
  end

  defp encode_command(command, params) do
    case Encoder.encode(command, params) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} -> {:error, :encoding_failed, reason}
    end
  end

  defp get_interface(target, opts) do
    interface_id = Keyword.get(opts, :interface_id)

    if interface_id do
      case Interfaces.get_interface(interface_id) do
        nil -> {:error, :unknown_interface}
        interface -> {:ok, interface}
      end
    else
      # Find a write interface for this target
      case Interfaces.list_interfaces_for_target(target, direction: "write") do
        [] -> {:error, :no_interface}
        [interface | _] -> {:ok, interface}
      end
    end
  end

  defp process_protocol_chain(interface, command_binary) do
    case ProtocolChain.whereis(interface.id) do
      nil ->
        # No protocol chain - return raw binary
        {:ok, command_binary}

      chain_pid ->
        ProtocolChain.process_write(chain_pid, command_binary)
    end
  end

  defp send_to_interface(interface, data) do
    # Look up the interface process
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:interface, interface.mission_id, interface.id}
         ) do
      [{pid, _}] ->
        case GenServer.call(pid, {:send_data, data}) do
          :ok -> :ok
          {:error, reason} -> {:error, :send_failed, reason}
        end

      [] ->
        {:error, :interface_not_running}
    end
  end

  # ============================================
  # RECORDING CREATION
  # ============================================

  defp create_command_recording(state, command, target, params, encoded, opts) do
    user_id = Keyword.get(opts, :user_id)
    aggregate_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    recordable_attrs = %{
      command_name: command.name,
      opcode: command.opcode,
      parameters: params,
      encoded_binary: encoded,
      meta_command_id: command.id,
      is_hazardous: command.is_hazardous || false
    }

    recording_attrs = %{
      organization_id: state.mission.organization_id,
      bucket_id: target.bucket_id,
      aggregate_id: aggregate_id,
      actor_id: user_id,
      actor_type: "user",
      timestamp: now
    }

    case Recordings.create(CommandDispatched, recordable_attrs, recording_attrs) do
      {:ok, %{recordable: _recordable, recording: recording}} ->
        {:ok, %{aggregate_id: aggregate_id, recording_id: recording.id}}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp record_command_sent(state, aggregate_id, parent_recording_id, interface_id) do
    now = DateTime.utc_now()

    recordable_attrs = %{interface_id: interface_id}

    recording_attrs = %{
      organization_id: state.mission.organization_id,
      bucket_id: state.target.bucket_id,
      aggregate_id: aggregate_id,
      parent_id: parent_recording_id,
      root_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    Recordings.create(CommandSent, recordable_attrs, recording_attrs)
  end

  defp record_command_verified(state, aggregate_id, parent_recording_id, verification_result) do
    now = DateTime.utc_now()

    recordable_attrs = %{
      verification_item: verification_result[:item],
      verification_expected: verification_result[:expected],
      verification_actual: verification_result[:actual],
      verification_result: verification_result[:result],
      stages_completed: verification_result[:stages_completed] || []
    }

    recording_attrs = %{
      organization_id: state.mission.organization_id,
      bucket_id: state.target.bucket_id,
      aggregate_id: aggregate_id,
      parent_id: parent_recording_id,
      root_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    Recordings.create(CommandVerified, recordable_attrs, recording_attrs)
  end

  defp record_command_verification_failed(state, aggregate_id, parent_recording_id, error_info) do
    now = DateTime.utc_now()

    recordable_attrs = %{
      error_reason: error_info[:error_reason],
      verification_actual: error_info[:actual],
      verification_expected: error_info[:expected]
    }

    recording_attrs = %{
      organization_id: state.mission.organization_id,
      bucket_id: state.target.bucket_id,
      aggregate_id: aggregate_id,
      parent_id: parent_recording_id,
      root_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    Recordings.create(CommandVerificationFailed, recordable_attrs, recording_attrs)
  end

  defp create_hazardous_confirmation(command_name, params, opts, state) do
    target = state.target

    # Use cache for command lookup (command should already be found since we got here)
    # Fall back to DB if cache not available
    command_result =
      case MetaCommandCache.get_by_name(state.mission_id, target.definition_set_id, command_name) do
        {:ok, command} ->
          {:ok, command}

        {:error, reason} when reason in [:not_found, :cache_not_available] ->
          case Commands.get_meta_command(target.definition_set_id, command_name) do
            nil -> {:error, :not_found}
            command -> {:ok, command}
          end
      end

    case command_result do
      {:ok, command} ->
        token = generate_token()
        expires_at = DateTime.add(DateTime.utc_now(), @confirmation_timeout_ms, :millisecond)

        request = %ConfirmationRequest{
          token: token,
          command_name: command_name,
          params: params,
          opts: opts,
          hazard_description: command.hazard_description,
          expires_at: expires_at
        }

        # Store in state for confirm_dispatch to retrieve
        new_state = %{
          state
          | pending_confirmations: Map.put(state.pending_confirmations, token, request)
        }

        confirmation_info = %{
          token: token,
          command_name: command_name,
          target_id: state.target_id,
          hazard_description: command.hazard_description,
          expires_at: expires_at
        }

        {:requires_confirmation, confirmation_info, new_state}

      {:error, :not_found} ->
        {:error, :unknown_command}
    end
  end

  defp start_verification(state, cmd_info, command, target) do
    # Verifiers are preloaded by MetaCommandCache, but fallback to DB lookup
    # may return command without verifiers preloaded
    verifiers =
      case command.verifiers do
        %Ecto.Association.NotLoaded{} ->
          Repo.preload(command, :verifiers).verifiers

        verifiers ->
          verifiers
      end

    # Use CommandVerifiers if defined, otherwise no verification
    if verifiers != nil and verifiers != [] do
      start_multi_stage_verification(state, cmd_info, verifiers, target)
    else
      # No verification configured
      state
    end
  end

  defp start_multi_stage_verification(state, cmd_info, verifiers, target) do
    case VerificationRunner.new(cmd_info.aggregate_id, state.mission_id, target.id, verifiers) do
      {:ok, runner} ->
        # Subscribe to telemetry updates (if not already subscribed)
        Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{state.mission_id}:telemetry")

        # Start the first stage
        case VerificationRunner.start_current_stage(runner) do
          {:ok, runner} ->
            # Start timeout for the current stage
            runner = VerificationRunner.start_timeout(runner, self())

            Logger.info(
              "Starting verification for aggregate_id=#{cmd_info.aggregate_id}, " <>
                "stage=#{VerificationRunner.current_stage(runner)}"
            )

            verification = %{
              type: :multi_stage,
              runner: runner,
              target_id: target.id,
              aggregate_id: cmd_info.aggregate_id,
              recording_id: cmd_info.recording_id
            }

            %{
              state
              | pending_verifications:
                  Map.put(state.pending_verifications, cmd_info.aggregate_id, verification)
            }

          {:complete, _runner} ->
            # No stages to verify (shouldn't happen with non-empty verifiers)
            Logger.warning("Multi-stage verification completed immediately with no stages")
            state
        end

      {:error, :no_verifiers} ->
        # Shouldn't happen since we checked for non-empty verifiers
        state
    end
  end

  defp check_simple_verification(state, aggregate_id, verification, actual_value) do
    # For simple verification, we just check that the item was updated (any value)
    Logger.info(
      "Simple command verification succeeded for aggregate_id=#{aggregate_id}, " <>
        "item=#{verification.item}, value=#{inspect(actual_value)}"
    )

    # Cancel timeout
    Process.cancel_timer(verification.timeout_ref)

    # Record verified event
    record_command_verified(state, aggregate_id, verification.recording_id, %{
      item: verification.item,
      actual: to_string(actual_value)
    })

    # Remove from pending
    %{state | pending_verifications: Map.delete(state.pending_verifications, aggregate_id)}
  end

  defp handle_multi_stage_update(
         state,
         aggregate_id,
         verification,
         runner,
         packet_name,
         item_name,
         value
       ) do
    case VerificationRunner.check_update(runner, packet_name, item_name, value) do
      {:stage_complete, updated_runner} ->
        Logger.info(
          "Verification stage #{VerificationRunner.current_stage(runner)} complete for " <>
            "aggregate_id=#{aggregate_id}, advancing to next stage"
        )

        # Start next stage
        case VerificationRunner.start_current_stage(updated_runner) do
          {:ok, runner_with_stage} ->
            # Start timeout for the new stage
            runner_with_timeout = VerificationRunner.start_timeout(runner_with_stage, self())

            updated_verification = %{verification | runner: runner_with_timeout}

            %{
              state
              | pending_verifications:
                  Map.put(state.pending_verifications, aggregate_id, updated_verification)
            }

          {:complete, final_runner} ->
            complete_multi_stage_verification(state, aggregate_id, verification, final_runner)
        end

      {:all_complete, final_runner} ->
        complete_multi_stage_verification(state, aggregate_id, verification, final_runner)

      {:failed, _runner, reason} ->
        Logger.warning("Verification failed for aggregate_id=#{aggregate_id}: #{inspect(reason)}")

        record_command_verification_failed(state, aggregate_id, verification.recording_id, %{
          error_reason: inspect(reason)
        })

        %{state | pending_verifications: Map.delete(state.pending_verifications, aggregate_id)}

      {:pending, updated_runner} ->
        updated_verification = %{verification | runner: updated_runner}

        %{
          state
          | pending_verifications:
              Map.put(state.pending_verifications, aggregate_id, updated_verification)
        }
    end
  end

  defp complete_multi_stage_verification(state, aggregate_id, verification, runner) do
    Logger.info(
      "All verification stages complete for aggregate_id=#{aggregate_id}, " <>
        "stages: #{inspect(VerificationRunner.completed_stages(runner))}"
    )

    record_command_verified(state, aggregate_id, verification.recording_id, %{
      stages_completed: Enum.map(VerificationRunner.completed_stages(runner), &to_string/1)
    })

    %{state | pending_verifications: Map.delete(state.pending_verifications, aggregate_id)}
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  # Extract mission and target from opts (entity-based only)
  defp extract_mission_and_target(opts) do
    case {Keyword.get(opts, :mission), Keyword.get(opts, :target)} do
      {%Mission{} = mission, %Target{} = target} ->
        {mission, target}

      _ ->
        raise ArgumentError,
              "TargetDispatcher requires (mission: entity, target: entity)"
    end
  end
end
