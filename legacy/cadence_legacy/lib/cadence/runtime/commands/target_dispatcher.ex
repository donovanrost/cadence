defmodule Cadence.Runtime.Commands.TargetDispatcher do
  @moduledoc """
  Target-scoped GenServer for command dispatch.

  One TargetDispatcher per target, managed by TargetPipeline supervisor.
  Handles command validation, encoding, and uplink dispatch for a single target.

  ## Command Lookup

  Commands are looked up via the target's definition_set_id, ensuring each target
  uses the correct command dictionary version.

  ## Responsibilities

  1. **Validation** - Validate arguments against Argument specs
  2. **Phase Checking** - Ensure command is allowed in current mission phase
  3. **Hazard Handling** - Require confirmation for hazardous commands
  4. **Encoding** - Encode command to binary format
  5. **PDU Build** - Wrap encoded command in a CCSDS PDU
  6. **Uplink Dispatch** - Emit the PDU to the uplink dispatcher
  7. **Logging** - Record all activity to command_logs table
  8. **Pause/Resume** - Control whether commands are sent to this target

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

  alias Cadence.Commands.CommandCompiler
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Recordings

  alias Cadence.Recordings.Recordables.{
    CommandDispatched,
    CommandErrored,
    CommandRejected,
    CommandSent
  }

  alias Cadence.Runtime.Commands.{TargetQueue, VerificationManager}
  alias Cadence.Runtime.Transport.COP1.Context, as: COP1Context
  alias Cadence.Runtime.Transport.ProtocolEvent
  alias Cadence.Runtime.Uplink.Dispatcher, as: UplinkDispatcher
  alias Cadence.Runtime.Uplink.UplinkPDU
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer
  alias Cadence.Transports.Events.TransportConnectionEvent

  @confirmation_timeout_ms 60_000
  @default_dispatch_timeout_ms 30_000
  @queue_check_interval_ms 100
  @dispatch_opts_key_map %{
    "transport_id" => :transport_id,
    "skip_verification" => :skip_verification,
    "skip_hazardous_check" => :skip_hazardous_check
  }

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
      # State flags
      paused: false,
      executing: false,
      pending_confirmations: %{},
      pending_cop1: %{}
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

  - `:transport_id` - Specific transport to use (optional)
  - `:user_id` - User performing the action (for audit)
  - `:skip_verification` - Don't auto-verify even if configured
  - `:skip_hazardous_check` - Bypass hazardous confirmation (dangerous!)

  ## Returns

  - `{:ok, command_recording_id}` - Command dispatched successfully
  - `{:error, :paused}` - Dispatcher is paused
  - `{:error, :requires_confirmation, %{token: ..., hazard_description: ...}}` - Hazardous command
  - `{:error, :validation_failed, errors}` - Argument validation failed
  - `{:error, :not_allowed_in_phase, current_phase}` - Phase restriction
  - `{:error, :unknown_command}` - Command not found
  - `{:error, :encoding_failed, reason}` - Binary encoding failed
  - `{:error, :missing_command_apid}` - No command APID configured for target
  - `{:error, :invalid_command_apid, apid}` - Invalid command APID value
  - `{:error, :no_transport}` - No uplink transport route for target
  - `{:error, :routing_ambiguous}` - Multiple active bindings with no routing hint
  - `{:error, :uplink_not_running}` - Uplink dispatcher not available
  - `{:error, :send_failed, reason}` - Uplink transmission failed
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
  def cancel_verification(mission_id, target_id, command_aggregate_id) do
    VerificationManager.cancel_verification(mission_id, target_id, command_aggregate_id)
  end

  @doc """
  Gets the status of a pending verification.
  """
  def verification_status(mission_id, target_id, command_aggregate_id) do
    VerificationManager.verification_status(mission_id, target_id, command_aggregate_id)
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
    Logger.debug("Starting TargetDispatcher for mission_id=#{mission.id} target_id=#{target.id}")

    Logger.info(
      "Starting TargetDispatcher for mission_id=#{mission.id}, target=#{target.identifier} (#{target.id})"
    )

    # Subscribe to transport connection events for this mission
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:events")

    state = %State{
      mission_id: mission.id,
      target_id: target.id,
      target: target,
      mission: mission,
      pending_confirmations: %{},
      pending_cop1: %{}
    }

    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping TargetDispatcher for mission_id=#{state.mission_id} target_id=#{state.target_id} reason=#{inspect(reason)}"
    )

    :ok
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
      {:ok, info, new_state} ->
        new_state = register_cop1_pending(new_state, info, nil)
        {:reply, {:ok, info.recording_id}, new_state}

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

  def handle_call(:status, _from, state) do
    uplink_connected = uplink_connected?(state)

    pending_verifications =
      if Code.ensure_loaded?(VerificationManager) do
        VerificationManager.pending_count(state.mission_id, state.target_id)
      else
        0
      end

    status = %{
      mission_id: state.mission_id,
      target_id: state.target_id,
      paused: state.paused,
      executing: state.executing,
      uplink_connected: uplink_connected,
      pending_confirmations: map_size(state.pending_confirmations),
      pending_verifications: pending_verifications
    }

    {:reply, status, state}
  end

  @impl true
  # Queue processing - triggered by TargetQueue when commands are available
  def handle_info(:check_queue, %{paused: true} = state) do
    {:noreply, state}
  end

  def handle_info(:check_queue, %{executing: true} = state) do
    # Already executing a command, will check again when done
    {:noreply, state}
  end

  def handle_info(:check_queue, state) do
    if uplink_connected?(state) do
      case TargetQueue.next(state.mission_id, state.target_id) do
        nil ->
          # No commands ready
          {:noreply, state}

        entry ->
          # Got a command - execute it
          new_state = process_queue_entry(entry, state)
          {:noreply, new_state}
      end
    else
      # No uplink route connected - wait for a connection event
      {:noreply, state}
    end
  end

  # Task.async completion - normal result
  def handle_info({ref, result}, %{dispatch_task: %Task{ref: ref}} = state) do
    # Clean up the monitor
    Process.demonitor(ref, [:flush])

    # Cancel the timeout timer
    if state.dispatch_timeout_ref do
      TimeTimer.cancel(state.dispatch_timeout_ref)
    end

    case result do
      {:ok, %{cop1_pending: true} = info} ->
        new_state = register_cop1_pending(state, info, state.executing_entry_id)

        {:noreply,
         %{
           new_state
           | dispatch_task: nil,
             dispatch_timeout_ref: nil
         }}

      _ ->
        # Report result back to queue
        TargetQueue.complete(state.mission_id, state.target_id, state.executing_entry_id, result)

        # Only check for more work if uplink is connected
        if uplink_connected?(state) do
          TimeTimer.send_after(self(), :check_queue, @queue_check_interval_ms)
        end

        {:noreply,
         %{
           state
           | executing: false,
             dispatch_task: nil,
             dispatch_timeout_ref: nil,
             executing_entry_id: nil
         }}
    end
  end

  # Task.async crash - the task process died
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{dispatch_task: %Task{ref: ref}} = state) do
    Logger.error(
      "Command dispatch task crashed for entry_id=#{state.executing_entry_id}: #{inspect(reason)}"
    )

    # Cancel the timeout timer
    if state.dispatch_timeout_ref do
      TimeTimer.cancel(state.dispatch_timeout_ref)
    end

    # Report failure to queue
    TargetQueue.complete(
      state.mission_id,
      state.target_id,
      state.executing_entry_id,
      {:error, :task_crashed, inspect(reason)}
    )

    # Check for more work after a brief delay
    TimeTimer.send_after(self(), :check_queue, @queue_check_interval_ms)

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
    TimeTimer.send_after(self(), :check_queue, @queue_check_interval_ms)

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

  def handle_info({:protocol_event, %ProtocolEvent{protocol: :cop1} = event}, state) do
    {pending, remaining} = Map.pop(state.pending_cop1, event.correlation_id)

    case pending do
      nil ->
        {:noreply, state}

      _ ->
        state =
          state
          |> Map.put(:pending_cop1, remaining)
          |> handle_cop1_event(pending, event)

        {:noreply, state}
    end
  end

  # Transport connection events - resume if a route becomes available
  def handle_info(
        {:transport_connection_event, %TransportConnectionEvent{} = event},
        state
      ) do
    if event.new_state == :connected and uplink_connected?(state) do
      Logger.info(
        "Transport #{event.transport_id} connected - resuming command dispatch for target #{state.target_id}"
      )

      # Trigger queue check now that we're connected
      send(self(), :check_queue)
    end

    {:noreply, state}
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
    DateTime.compare(CadenceTime.now(), expires_at) == :gt
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
      {:ok, info, new_state} ->
        new_state = register_cop1_pending(new_state, info, nil)
        {:reply, {:ok, info.recording_id}, new_state}

      {:error, _} = error ->
        {:reply, error, state_without_confirmation}

      {:error, _, _} = error ->
        {:reply, error, state_without_confirmation}
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
          |> dispatch_opts_to_keyword_list()
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
    timeout_ref = TimeTimer.send_after(self(), :dispatch_timeout, dispatch_timeout)

    %{
      state
      | executing: true,
        dispatch_task: task,
        dispatch_timeout_ref: timeout_ref,
        executing_entry_id: entry.id
    }
  end

  defp register_cop1_pending(%State{} = state, %{cop1_pending: true} = info, entry_id) do
    pending =
      Map.put(state.pending_cop1, info.correlation_id, %{
        aggregate_id: info.aggregate_id,
        recording_id: info.recording_id,
        entry_id: entry_id,
        command_name: Map.get(info, :command_name)
      })

    %{state | pending_cop1: pending}
  end

  defp register_cop1_pending(%State{} = state, _info, _entry_id), do: state

  defp handle_cop1_event(%State{} = state, pending, %ProtocolEvent{} = event) do
    case event.status do
      :accepted ->
        record_command_sent(state, pending.aggregate_id, pending.recording_id, event.transport_id)

        maybe_complete_queue_entry(
          state,
          pending.entry_id,
          {:ok, %{aggregate_id: pending.aggregate_id}}
        )

      :rejected ->
        record_command_errored(state, pending.aggregate_id, pending.command_name, %{
          error_type: "cop1_rejected",
          error_reason: cop1_error_reason(event)
        })

        maybe_complete_queue_entry(
          state,
          pending.entry_id,
          {:error, :cop1_rejected, event.reason}
        )

      :timeout ->
        record_command_errored(state, pending.aggregate_id, pending.command_name, %{
          error_type: "cop1_timeout",
          error_reason: cop1_error_reason(event)
        })

        maybe_complete_queue_entry(state, pending.entry_id, {:error, :cop1_timeout, event.reason})

      _ ->
        state
    end
  end

  defp maybe_complete_queue_entry(%State{} = state, nil, _result), do: state

  defp maybe_complete_queue_entry(%State{} = state, entry_id, result) do
    TargetQueue.complete(state.mission_id, state.target_id, entry_id, result)

    state =
      if state.executing_entry_id == entry_id do
        %{state | executing: false, executing_entry_id: nil}
      else
        state
      end

    if uplink_connected?(state) do
      TimeTimer.send_after(self(), :check_queue, @queue_check_interval_ms)
    end

    state
  end

  defp cop1_error_reason(%ProtocolEvent{} = event) do
    case event.reason do
      nil -> "COP-1 #{event.status}"
      reason -> "COP-1 #{event.status}: #{inspect(reason)}"
    end
  end

  defp dispatch_opts_to_keyword_list(dispatch_opts) when is_map(dispatch_opts) do
    Enum.flat_map(dispatch_opts, fn {key, value} ->
      case Map.get(@dispatch_opts_key_map, normalize_dispatch_opt_key(key)) do
        nil -> []
        atom_key -> [{atom_key, value}]
      end
    end)
  end

  defp dispatch_opts_to_keyword_list(_dispatch_opts), do: []

  defp normalize_dispatch_opt_key(key) when is_binary(key), do: key
  defp normalize_dispatch_opt_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_dispatch_opt_key(_key), do: nil

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

    # Get aggregate_id from entry (generated at enqueue time) or generate for direct dispatch
    aggregate_id = Map.get(entry, :command_aggregate_id) || Ecto.UUID.generate()

    Logger.info(
      "[DISPATCH] command_name=#{inspect(entry.command_name)}, " <>
        "mission_id=#{inspect(state.mission_id)}, target_id=#{target.id}, " <>
        "definition_set_id=#{inspect(target.definition_set_id)}"
    )

    with {:ok, command} <-
           CommandCompiler.fetch_command(
             state.mission_id,
             target.definition_set_id,
             entry.command_name
           ),
         :ok <- check_phase_restriction(command, state.mission),
         :ok <- check_hazardous(command, entry.parameters, opts, state),
         {:ok, compiled} <-
           CommandCompiler.compile(command, entry.parameters, target, aggregate_id),
         {:ok, cmd_info} <-
           create_command_recording(
             state,
             command,
             target,
             entry.parameters,
             compiled.encoded,
             opts,
             aggregate_id
           ),
         opts = Keyword.put(opts, :command_id, command.id),
         correlation_id = %{
           aggregate_id: cmd_info.aggregate_id,
           recording_id: cmd_info.recording_id,
           target_id: target.id
         },
         {:ok, decision} <-
           dispatch_pdu(
             state,
             target,
             compiled.pdu,
             put_cop1_context(opts, correlation_id)
           ) do
      info = %{
        aggregate_id: cmd_info.aggregate_id,
        correlation_id: correlation_id,
        recording_id: cmd_info.recording_id,
        command_name: command.name
      }

      info =
        if decision.cop1_mode == :fop do
          Map.put(info, :cop1_pending, true)
        else
          record_command_sent(
            state,
            cmd_info.aggregate_id,
            cmd_info.recording_id,
            decision.transport_id
          )

          info
        end

      # Start verification if configured (using verifiers association)
      new_state =
        if Keyword.get(opts, :skip_verification, false) do
          state
        else
          start_verification(state, cmd_info, command, target)
        end

      {:ok, info, new_state}
    else
      {:error, :requires_confirmation, _} ->
        # Handle hazardous command - store confirmation request and return info
        create_hazardous_confirmation(entry.command_name, entry.parameters, opts, state)

      {:error, :unknown_command} = error ->
        record_command_rejected(state, aggregate_id, entry.command_name, %{
          rejection_type: "validation",
          error_reason: "Unknown command: #{entry.command_name}"
        })

        error

      {:error, :not_allowed_in_phase, phase} = error ->
        record_command_rejected(state, aggregate_id, entry.command_name, %{
          rejection_type: "phase",
          error_reason: "Command not allowed in phase: #{phase}"
        })

        error

      {:error, :validation_failed, errors} = error ->
        record_command_rejected(state, aggregate_id, entry.command_name, %{
          rejection_type: "validation",
          error_reason: inspect(errors)
        })

        error

      {:error, :encoding_failed, reason} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "encoding",
          error_reason: inspect(reason)
        })

        error

      {:error, :missing_command_apid} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "missing_command_apid",
          error_reason: "No command APID configured for target"
        })

        error

      {:error, {:invalid_command_apid, apid}} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "invalid_command_apid",
          error_reason: "Invalid command APID: #{inspect(apid)}"
        })

        error

      {:error, :missing_apid} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "missing_apid",
          error_reason: "Missing APID on PDU"
        })

        error

      {:error, :no_transport} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "no_transport",
          error_reason: "No transport available for target"
        })

        error

      {:error, :routing_ambiguous} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "routing_ambiguous",
          error_reason: "Multiple active uplink bindings; specify a transport or channel"
        })

        error

      {:error, :uplink_not_running} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "uplink_not_running",
          error_reason: "Uplink dispatcher not running"
        })

        error

      {:error, :transport_not_running} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "transport_disconnected",
          error_reason: "Transport not running"
        })

        error

      {:error, :send_failed, reason} = error ->
        record_command_errored(state, aggregate_id, entry.command_name, %{
          error_type: "send_failed",
          error_reason: inspect(reason)
        })

        error

      {:defer, reason} ->
        {:defer, reason}

      {:error, _} = error ->
        error

      {:error, _, _} = error ->
        error
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

  defp put_cop1_context(opts, correlation_id) when not is_nil(correlation_id) do
    base_context = COP1Context.new(%{correlation_id: correlation_id})

    case Keyword.get(opts, :cop1_context) do
      nil ->
        Keyword.put(opts, :cop1_context, base_context)

      %COP1Context{} = context ->
        Keyword.put(opts, :cop1_context, COP1Context.merge(base_context, context))

      _ ->
        opts
    end
  end

  defp put_cop1_context(opts, _correlation_id), do: opts

  defp dispatch_pdu(state, target, pdu, opts) do
    case uplink_dispatcher_pid(state.mission_id) do
      nil ->
        {:error, :uplink_not_running}

      _pid ->
        UplinkDispatcher.dispatch_pdu(state.mission_id, UplinkPDU.from_pdu(target.id, pdu), opts)
    end
  end

  # ============================================
  # RECORDING CREATION
  # ============================================

  defp create_command_recording(state, command, target, params, encoded, opts, aggregate_id) do
    user_id = Keyword.get(opts, :user_id)
    now = CadenceTime.now()

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

  defp record_command_sent(state, aggregate_id, parent_recording_id, transport_id) do
    now = CadenceTime.now()

    recordable_attrs = %{transport_id: transport_id}

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

  defp record_command_rejected(state, aggregate_id, command_name, error_info) do
    now = CadenceTime.now()

    recordable_attrs = %{
      error_reason: error_info[:error_reason],
      rejection_type: error_info[:rejection_type]
    }

    recording_attrs = %{
      organization_id: state.mission.organization_id,
      bucket_id: state.target.bucket_id,
      aggregate_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    case Recordings.create(CommandRejected, recordable_attrs, recording_attrs) do
      {:ok, _} ->
        Logger.info(
          "[DISPATCH] Recorded command rejection: command=#{command_name}, " <>
            "type=#{error_info[:rejection_type]}, reason=#{error_info[:error_reason]}"
        )

      {:error, _, changeset, _} ->
        Logger.warning(
          "[DISPATCH] Failed to record command rejection: #{inspect(changeset.errors)}"
        )
    end
  end

  defp record_command_errored(state, aggregate_id, command_name, error_info) do
    now = CadenceTime.now()

    recordable_attrs = %{
      error_reason: error_info[:error_reason],
      error_type: error_info[:error_type]
    }

    recording_attrs = %{
      organization_id: state.mission.organization_id,
      bucket_id: state.target.bucket_id,
      aggregate_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    case Recordings.create(CommandErrored, recordable_attrs, recording_attrs) do
      {:ok, _} ->
        Logger.info(
          "[DISPATCH] Recorded command error: command=#{command_name}, " <>
            "type=#{error_info[:error_type]}, reason=#{error_info[:error_reason]}"
        )

      {:error, _, changeset, _} ->
        Logger.warning("[DISPATCH] Failed to record command error: #{inspect(changeset.errors)}")
    end
  end

  defp create_hazardous_confirmation(command_name, params, opts, state) do
    target = state.target

    case CommandCompiler.fetch_command(state.mission_id, target.definition_set_id, command_name) do
      {:ok, command} ->
        token = generate_token()
        expires_at = DateTime.add(CadenceTime.now(), @confirmation_timeout_ms, :millisecond)

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

      {:error, :unknown_command} ->
        {:error, :unknown_command}
    end
  end

  defp start_verification(state, cmd_info, command, target) do
    verifiers = load_verifiers(command)

    if verifiers != nil and verifiers != [] do
      case VerificationManager.start_verification(state.mission_id, %{
             aggregate_id: cmd_info.aggregate_id,
             recording_id: cmd_info.recording_id,
             target_id: target.id,
             organization_id: state.mission.organization_id,
             bucket_id: target.bucket_id,
             verifiers: verifiers
           }) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to start verification for aggregate_id=#{cmd_info.aggregate_id}: #{inspect(reason)}"
          )
      end
    end

    state
  end

  defp load_verifiers(command) do
    case command.verifiers do
      %Ecto.Association.NotLoaded{} ->
        Logger.warning("Command verifiers not preloaded; skipping verification for #{command.id}")
        []

      verifiers ->
        verifiers
    end
  end

  defp uplink_connected?(%State{} = state) do
    case uplink_dispatcher_pid(state.mission_id) do
      nil ->
        false

      pid ->
        try do
          GenServer.call(pid, {:connected?, state.target_id})
        catch
          :exit, _ -> false
        end
    end
  end

  defp uplink_dispatcher_pid(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:uplink_dispatcher, mission_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
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
