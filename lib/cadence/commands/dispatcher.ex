defmodule Cadence.Commands.Dispatcher do
  @moduledoc """
  Mission-scoped GenServer for command dispatch and verification.

  One Dispatcher per mission, managed by MissionInstance supervisor.
  Handles command validation, encoding, routing, and verification.

  ## Responsibilities

  1. **Validation** - Validate parameters against CommandParameter specs
  2. **Phase Checking** - Ensure command is allowed in current mission phase
  3. **Hazard Handling** - Require confirmation for hazardous commands
  4. **Encoding** - Encode command to binary format
  5. **Routing** - Find appropriate interface for target
  6. **Transmission** - Send through protocol chain and interface
  7. **Verification** - Monitor CVT for verification (if configured)
  8. **Logging** - Record all activity to command_logs table

  ## Example

      # Basic command dispatch
      {:ok, cmd_id} = Dispatcher.dispatch(mission_id, "SET_MODE", %{mode: 1}, target: "SC1")

      # Hazardous command returns confirmation request
      {:error, :requires_confirmation, info} = Dispatcher.dispatch(mission_id, "SAFE_MODE", %{})

      # Confirm and dispatch
      {:ok, cmd_id} = Dispatcher.confirm_dispatch(mission_id, info.token)
  """

  use GenServer
  require Logger

  alias Cadence.{Repo, Missions, Targets, Interfaces}
  alias Cadence.Commands
  alias Cadence.Commands.{CommandDefinition, CommandLog, Encoder}
  alias Cadence.Telemetry.ProtocolChain

  @confirmation_timeout_ms 60_000
  @default_verification_timeout_ms 5_000

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :mission,
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
  Starts dispatcher for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :dispatcher}}}
  end

  @doc """
  Returns the PID of a dispatcher by mission_id.
  """
  def whereis(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {mission_id, :dispatcher}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Dispatches a command to a target.

  ## Options

  - `:target` or `:target_id` - Target ID or identifier (required)
  - `:interface_id` - Specific interface to use (optional)
  - `:user_id` - User performing the action (for audit)
  - `:skip_verification` - Don't auto-verify even if configured
  - `:skip_hazardous_check` - Bypass hazardous confirmation (dangerous!)

  ## Returns

  - `{:ok, command_log_id}` - Command sent successfully
  - `{:error, :requires_confirmation, %{token: ..., hazard_description: ...}}` - Hazardous command
  - `{:error, :validation_failed, errors}` - Parameter validation failed
  - `{:error, :not_allowed_in_phase, current_phase}` - Phase restriction
  - `{:error, :unknown_command}` - Command not found
  - `{:error, :unknown_target}` - Target not found
  - `{:error, :no_interface}` - No write interface for target
  - `{:error, :interface_disconnected}` - Interface not connected
  - `{:error, :encoding_failed, reason}` - Binary encoding failed
  - `{:error, :send_failed, reason}` - Transmission failed
  """
  def dispatch(mission_id, command_name, params, opts \\ []) do
    GenServer.call(via_tuple(mission_id), {:dispatch, command_name, params, opts})
  end

  @doc """
  Confirms and dispatches a hazardous command using a confirmation token.
  """
  def confirm_dispatch(mission_id, token) do
    GenServer.call(via_tuple(mission_id), {:confirm_dispatch, token})
  end

  @doc """
  Cancels a pending verification.
  """
  def cancel_verification(mission_id, command_log_id) do
    GenServer.cast(via_tuple(mission_id), {:cancel_verification, command_log_id})
  end

  @doc """
  Gets the status of a pending verification.
  """
  def verification_status(mission_id, command_log_id) do
    GenServer.call(via_tuple(mission_id), {:verification_status, command_log_id})
  end

  @doc """
  Gets dispatcher statistics.
  """
  def stats(mission_id) do
    GenServer.call(via_tuple(mission_id), :stats)
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting CommandDispatcher for mission_id=#{mission_id}")

    # Load mission for phase checking
    mission = Missions.get_mission!(mission_id)

    state = %State{
      mission_id: mission_id,
      mission: mission
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:dispatch, command_name, params, opts}, _from, state) do
    case do_dispatch(command_name, params, opts, state) do
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

      %ConfirmationRequest{expires_at: expires_at} = request ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
          # Token expired
          new_state = %{
            state
            | pending_confirmations: Map.delete(state.pending_confirmations, token)
          }

          {:reply, {:error, :token_expired}, new_state}
        else
          # Execute the command with hazardous check skipped
          opts = Keyword.put(request.opts, :skip_hazardous_check, true)

          # Remove the confirmation from pending before dispatch
          state_without_confirmation = %{
            state
            | pending_confirmations: Map.delete(state.pending_confirmations, token)
          }

          case do_dispatch(request.command_name, request.params, opts, state_without_confirmation) do
            {:ok, command_log_id, new_state} ->
              {:reply, {:ok, command_log_id}, new_state}

            {:error, _} = error ->
              {:reply, error, state_without_confirmation}

            {:error, _, _} = error ->
              {:reply, error, state_without_confirmation}
          end
        end
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

  def handle_call(:stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      pending_confirmations: map_size(state.pending_confirmations),
      pending_verifications: map_size(state.pending_verifications),
      command_counter: state.command_counter
    }

    {:reply, stats, state}
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
  def handle_info({:verification_timeout, command_log_id}, state) do
    case Map.get(state.pending_verifications, command_log_id) do
      nil ->
        {:noreply, state}

      _verification ->
        Logger.warning("Command verification timeout for command_log_id=#{command_log_id}")

        # Update command log status
        update_command_log_status(command_log_id, :verification_failed, %{
          error_reason: "Verification timeout"
        })

        new_state = %{
          state
          | pending_verifications: Map.delete(state.pending_verifications, command_log_id)
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:telemetry_update, target_id, packet_name, item_name, telemetry_value}, state) do
    # Check if any pending verification matches this update
    full_item = "#{packet_name}.#{item_name}"

    state =
      Enum.reduce(state.pending_verifications, state, fn {cmd_log_id, verification}, acc ->
        if verification.target_id == target_id and verification.item == full_item do
          check_verification(acc, cmd_log_id, verification, telemetry_value.value)
        else
          acc
        end
      end)

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp do_dispatch(command_name, params, opts, state) do
    # Get target first - it has the definition_set_id for command lookup
    with {:ok, target} <- get_target(state.mission_id, opts),
         {:ok, command} <- get_command(target.definition_set_id, command_name),
         :ok <- check_phase_restriction(command, state.mission),
         :ok <- check_hazardous(command, params, opts, state),
         :ok <- validate_params(command, params),
         {:ok, encoded} <- encode_command(command, params),
         {:ok, interface} <- get_interface(target, opts),
         {:ok, framed} <- process_protocol_chain(interface, encoded),
         {:ok, command_log} <- create_command_log(state, command, target, params, encoded, opts),
         :ok <- send_to_interface(interface, framed) do
      # Update log to sent status
      update_command_log_status(command_log.id, :sent, %{sent_at: DateTime.utc_now()})

      # Start verification if configured
      new_state =
        if command.has_verification and not Keyword.get(opts, :skip_verification, false) do
          start_verification(state, command_log.id, command, target)
        else
          state
        end

      {:ok, command_log.id, new_state}
    else
      {:error, :requires_confirmation, _} ->
        # Handle hazardous command - store confirmation request and return info
        create_hazardous_confirmation(command_name, params, opts, state)

      {:error, _} = error ->
        error

      {:error, _, _} = error ->
        error
    end
  end

  defp get_command(definition_set_id, command_name) do
    case Commands.get_command_by_name(definition_set_id, command_name) do
      nil -> {:error, :unknown_command}
      command -> {:ok, command}
    end
  end

  defp get_target(_mission_id, opts) do
    target_id = Keyword.get(opts, :target) || Keyword.get(opts, :target_id)

    if is_nil(target_id) do
      {:error, :target_required}
    else
      case Targets.get_target!(target_id) do
        nil -> {:error, :unknown_target}
        target -> {:ok, target}
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, :unknown_target}
  end

  defp check_phase_restriction(%CommandDefinition{} = command, mission) do
    if CommandDefinition.allowed_in_phase?(command, mission.phase) do
      :ok
    else
      {:error, :not_allowed_in_phase, mission.phase}
    end
  end

  defp check_hazardous(command, _params, opts, _state) do
    skip_check = Keyword.get(opts, :skip_hazardous_check, false)

    if not skip_check and CommandDefinition.requires_confirmation?(command) do
      {:error, :requires_confirmation, command.hazard_description}
    else
      :ok
    end
  end

  defp validate_params(command, params) do
    case Commands.validate_parameters(command, params) do
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

  defp create_command_log(state, command, target, params, encoded, opts) do
    user_id = Keyword.get(opts, :user_id)
    interface_id = Keyword.get(opts, :interface_id)

    attrs = %{
      organization_id: state.mission.organization_id,
      mission_id: state.mission_id,
      target_id: target.id,
      command_definition_id: command.id,
      user_id: user_id,
      command_name: command.name,
      opcode: command.opcode,
      parameters: params,
      encoded_binary: encoded,
      status: :pending,
      verification_item: command.verification_item,
      metadata: %{interface_id: interface_id}
    }

    %CommandLog{}
    |> CommandLog.changeset(attrs)
    |> Repo.insert()
  end

  defp update_command_log_status(command_log_id, status, extra_attrs) do
    case Repo.get(CommandLog, command_log_id) do
      nil ->
        Logger.warning("CommandLog not found: #{command_log_id}")

      log ->
        attrs = Map.merge(%{status: status}, extra_attrs)

        log
        |> CommandLog.status_changeset(attrs)
        |> Repo.update()
    end
  end

  defp create_hazardous_confirmation(command_name, params, opts, state) do
    # Get target for its definition_set_id
    target_id = Keyword.get(opts, :target) || Keyword.get(opts, :target_id)
    target = target_id && Targets.get_target!(target_id)
    definition_set_id = target && target.definition_set_id

    # Get command for hazard description
    case definition_set_id && Commands.get_command_by_name(definition_set_id, command_name) do
      nil ->
        {:error, :unknown_command}

      command ->
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
          hazard_description: command.hazard_description,
          expires_at: expires_at
        }

        {:requires_confirmation, confirmation_info, new_state}
    end
  end

  defp start_verification(state, command_log_id, command, target) do
    timeout_ms = command.verification_timeout_ms || @default_verification_timeout_ms

    # Subscribe to telemetry updates (if not already subscribed)
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{state.mission_id}:telemetry")

    # Start timeout timer
    timeout_ref = Process.send_after(self(), {:verification_timeout, command_log_id}, timeout_ms)

    verification = %{
      item: command.verification_item,
      target_id: target.id,
      timeout_ref: timeout_ref,
      started_at: DateTime.utc_now()
    }

    # Return updated state with pending verification
    %{
      state
      | pending_verifications: Map.put(state.pending_verifications, command_log_id, verification)
    }
  end

  defp check_verification(state, command_log_id, verification, actual_value) do
    # For now, we just check that the item was updated (any value)
    # In the future, we could compare against expected values
    Logger.info(
      "Command verification succeeded for command_log_id=#{command_log_id}, " <>
        "item=#{verification.item}, value=#{inspect(actual_value)}"
    )

    # Cancel timeout
    Process.cancel_timer(verification.timeout_ref)

    # Update command log
    update_command_log_status(command_log_id, :verified, %{
      verified_at: DateTime.utc_now(),
      verification_actual: to_string(actual_value)
    })

    # Remove from pending
    %{state | pending_verifications: Map.delete(state.pending_verifications, command_log_id)}
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
