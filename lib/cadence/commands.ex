defmodule Cadence.Commands do
  @moduledoc """
  Context module for spacecraft command operations.

  Commands are defined in the MissionDatabase as MetaCommands within a DefinitionSet.
  Each Target references a specific DefinitionSet version, which determines
  which command dictionary is used for that target.

  ## Command Lookup

  Commands are looked up via the target's definition_set_id:

      # Get command for a target's definition set
      command = Commands.get_meta_command(definition_set_id, "SAFE_MODE")

  ## Safety Features

  Commands support safety metadata per ADR-004:

  - Hazardous command flagging
  - Operator confirmation requirements
  - Mission phase restrictions

  ## Example

      # List commands for a target's definition set
      commands = Commands.list_meta_commands(definition_set_id)

      # Get a specific command by name
      cmd = Commands.get_meta_command(definition_set_id, "SAFE_MODE")

      # Validate command arguments
      :ok = Commands.validate_arguments(cmd, %{"target_temp" => 25.0})
  """

  import Ecto.Query

  alias Cadence.Repo

  alias Cadence.MissionDatabase.{MetaCommand, Argument}

  alias Cadence.Commands.{
    TargetDispatcher,
    TargetQueue,
    TargetPipelineSupervisor,
    QueueEntry,
    Staging
  }

  alias Cadence.Recordings

  alias Cadence.{Missions, Targets}

  alias Cadence.Telemetry.CurrentValueTable

  # ============================================================================
  # MetaCommand Lookup Operations
  # ============================================================================

  @doc """
  Gets a MetaCommand by name for a DefinitionSet.

  This is the primary lookup method for command dispatch.
  Preloads arguments and verifiers for command execution.
  """
  def get_meta_command(definition_set_id, name) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.name == ^name,
      preload: [:arguments, :verifiers],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a MetaCommand by ID.
  """
  def get_meta_command_by_id(id) do
    MetaCommand
    |> Repo.get(id)
    |> Repo.preload([:arguments, :verifiers])
  end

  @doc """
  Gets a MetaCommand by ID, raising if not found.
  """
  def get_meta_command_by_id!(id) do
    MetaCommand
    |> Repo.get!(id)
    |> Repo.preload([:arguments, :verifiers])
  end

  @doc """
  Gets a MetaCommand by opcode for a DefinitionSet.
  """
  def get_meta_command_by_opcode(definition_set_id, opcode) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.opcode == ^opcode,
      preload: [:arguments, :verifiers],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all MetaCommands for a DefinitionSet.
  """
  def list_meta_commands(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.abstract == false or is_nil(c.abstract),
      order_by: [asc: c.name],
      preload: :arguments
    )
    |> Repo.all()
  end

  @doc """
  Lists hazardous MetaCommands for a DefinitionSet.
  """
  def list_hazardous_meta_commands(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.is_hazardous == true,
      order_by: [asc: c.name],
      preload: :arguments
    )
    |> Repo.all()
  end

  @doc """
  Lists MetaCommands allowed in a specific mission phase.
  """
  def list_meta_commands_for_phase(definition_set_id, phase) do
    list_meta_commands(definition_set_id)
    |> Enum.filter(&MetaCommand.allowed_in_phase?(&1, phase))
  end

  @doc """
  Counts MetaCommands in a DefinitionSet.
  """
  def count_meta_commands(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      select: count(c.id)
    )
    |> Repo.one()
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validates command arguments against argument definitions.

  Returns `:ok` if all validations pass, or `{:error, errors}` with a list
  of validation errors.

  ## Example

      case Commands.validate_arguments(command, %{"target_temp" => 25.0}) do
        :ok -> send_command(command, args)
        {:error, errors} -> handle_validation_errors(errors)
      end
  """
  def validate_arguments(%MetaCommand{} = command, args) when is_map(args) do
    command = Repo.preload(command, :arguments)

    errors =
      command.arguments
      |> Enum.flat_map(fn arg ->
        validate_single_argument(arg, args)
      end)

    # Check for unknown arguments
    known_names = MapSet.new(command.arguments, & &1.name)

    unknown_errors =
      args
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(known_names, to_string(&1)))
      |> Enum.map(fn name -> {name, "unknown argument"} end)

    all_errors = errors ++ unknown_errors

    if Enum.empty?(all_errors) do
      :ok
    else
      {:error, all_errors}
    end
  end

  defp validate_single_argument(%Argument{} = arg, args) do
    value = Map.get(args, arg.name) || Map.get(args, String.to_atom(arg.name))

    cond do
      # Required argument missing
      arg.required && is_nil(value) ->
        [{arg.name, "is required"}]

      # Optional argument not provided - OK
      is_nil(value) ->
        []

      # Validate the provided value
      true ->
        validate_argument_value(arg, value)
    end
  end

  defp validate_argument_value(%Argument{} = arg, value) do
    errors = []

    # Type validation based on data_type_ref
    errors =
      case validate_type(arg.data_type_ref, value) do
        :ok -> errors
        {:error, reason} -> [{arg.name, reason} | errors]
      end

    # Range validation
    errors =
      case validate_range(arg, value) do
        :ok -> errors
        {:error, reason} -> [{arg.name, reason} | errors]
      end

    # Valid values validation (for enums)
    errors =
      case validate_valid_values(arg, value) do
        :ok -> errors
        {:error, reason} -> [{arg.name, reason} | errors]
      end

    errors
  end

  defp validate_type("uint", value) when is_integer(value) and value >= 0, do: :ok
  defp validate_type("int", value) when is_integer(value), do: :ok
  defp validate_type("float", value) when is_number(value), do: :ok
  defp validate_type("string", value) when is_binary(value), do: :ok
  defp validate_type("boolean", value) when is_boolean(value), do: :ok
  defp validate_type("bool", value) when is_boolean(value), do: :ok
  defp validate_type("enum", value) when is_binary(value), do: :ok
  defp validate_type(nil, _value), do: :ok
  defp validate_type(type, _value), do: {:error, "invalid type for #{type}"}

  defp validate_range(%Argument{min_value: nil, max_value: nil}, _value), do: :ok

  defp validate_range(%Argument{min_value: min, max_value: max}, value) when is_number(value) do
    cond do
      min && value < min -> {:error, "value must be >= #{min}"}
      max && value > max -> {:error, "value must be <= #{max}"}
      true -> :ok
    end
  end

  defp validate_range(_, _), do: :ok

  defp validate_valid_values(%Argument{valid_values: []}, _value), do: :ok
  defp validate_valid_values(%Argument{valid_values: nil}, _value), do: :ok

  defp validate_valid_values(%Argument{valid_values: valid_values}, value)
       when is_binary(value) do
    if value in valid_values do
      :ok
    else
      {:error, "value must be one of: #{Enum.join(valid_values, ", ")}"}
    end
  end

  defp validate_valid_values(_, _), do: :ok

  # ============================================================================
  # Command Dispatch Operations
  # ============================================================================

  @doc """
  Dispatches a command to a target spacecraft.

  ## Options

  - `:target` or `:target_id` - Target ID or identifier (required)
  - `:interface_id` - Specific interface to use (optional)
  - `:user_id` - User performing the action (for audit)
  - `:skip_verification` - Don't auto-verify even if configured

  ## Returns

  - `{:ok, command_log_id}` - Command sent successfully
  - `{:error, :requires_confirmation, %{token: ..., hazard_description: ...}}` - Hazardous command needs confirmation
  - `{:error, :validation_failed, errors}` - Argument validation failed
  - `{:error, :not_allowed_in_phase, current_phase}` - Phase restriction
  - `{:error, :unknown_command}` - Command not found
  - `{:error, :unknown_target}` - Target not found
  - `{:error, :no_interface}` - No write interface for target
  - `{:error, :encoding_failed, reason}` - Binary encoding failed
  - `{:error, :send_failed, reason}` - Transmission failed
  - `{:error, :paused}` - Dispatcher is paused for this target

  ## Example

      {:ok, cmd_id} = Commands.dispatch(mission_id, "SET_MODE", %{mode: 1}, target: target_id)

      # Hazardous command
      {:error, :requires_confirmation, %{token: token}} = Commands.dispatch(mission_id, "SAFE_MODE", %{}, target: target_id)
      {:ok, cmd_id} = Commands.confirm_dispatch(mission_id, target_id, token)
  """
  @spec dispatch(String.t(), String.t(), map(), keyword()) ::
          {:ok, String.t()}
          | {:error, atom()}
          | {:error, atom(), term()}
  def dispatch(mission_id, command_name, params, opts \\ []) do
    target_id = get_target_id!(opts)

    case TargetDispatcher.whereis(mission_id, target_id) do
      nil ->
        {:error, :dispatcher_not_running}

      _pid ->
        TargetDispatcher.dispatch(mission_id, target_id, command_name, params, opts)
    end
  end

  @doc """
  Confirms and dispatches a hazardous command using a confirmation token.

  Call this after receiving `{:error, :requires_confirmation, %{token: token}}`
  from `dispatch/4`.

  ## Returns

  - `{:ok, command_log_id}` - Command sent successfully
  - `{:error, :invalid_token}` - Token not found
  - `{:error, :token_expired}` - Confirmation window expired
  """
  @spec confirm_dispatch(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def confirm_dispatch(mission_id, target_id, token) do
    TargetDispatcher.confirm_dispatch(mission_id, target_id, token)
  end

  @doc """
  Script-driven verification check.

  Waits for a CVT item to reach an expected value. This is used for explicit
  verification in scripts or procedures, as opposed to the automatic verification
  configured on MetaCommand.

  ## Options

  - `:timeout` - Max wait time in ms (default: 5000)
  - `:poll_interval` - How often to check in ms (default: 100)
  - `:comparison` - :eq, :gt, :lt, :gte, :lte, :ne (default: :eq)

  ## Returns

  - `:ok` - Value matched
  - `{:error, :timeout}` - Timeout before match
  - `{:error, :mismatch, actual_value}` - Final value didn't match

  ## Example

      Commands.dispatch(mission_id, "ENABLE_HEATER", %{id: 1}, target: target_id)

      case Commands.wait_check(mission_id, target_id, "THERMAL.HEATER_1_STATUS", "ON") do
        :ok -> Logger.info("Heater enabled")
        {:error, :timeout} -> Logger.error("Verification timeout")
        {:error, :mismatch, actual} -> Logger.error("Expected ON, got \#{actual}")
      end
  """
  @spec wait_check(String.t(), String.t(), String.t(), term(), keyword()) ::
          :ok | {:error, :timeout} | {:error, :mismatch, term()}
  def wait_check(mission_id, target_id, item, expected, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    poll_interval = Keyword.get(opts, :poll_interval, 100)
    comparison = Keyword.get(opts, :comparison, :eq)

    # Parse item into packet_name and item_name
    [packet_name, item_name] = String.split(item, ".", parts: 2)

    deadline = System.monotonic_time(:millisecond) + timeout

    poll_cvt(
      mission_id,
      target_id,
      packet_name,
      item_name,
      expected,
      comparison,
      poll_interval,
      deadline
    )
  end

  defp poll_cvt(
         mission_id,
         target_id,
         packet_name,
         item_name,
         expected,
         comparison,
         interval,
         deadline
       ) do
    case CurrentValueTable.get(mission_id, target_id, packet_name, item_name) do
      {:ok, %{value: value}} ->
        if compare_value(value, expected, comparison) do
          :ok
        else
          if System.monotonic_time(:millisecond) >= deadline do
            {:error, :mismatch, value}
          else
            Process.sleep(interval)

            poll_cvt(
              mission_id,
              target_id,
              packet_name,
              item_name,
              expected,
              comparison,
              interval,
              deadline
            )
          end
        end

      {:error, :not_found} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(interval)

          poll_cvt(
            mission_id,
            target_id,
            packet_name,
            item_name,
            expected,
            comparison,
            interval,
            deadline
          )
        end
    end
  end

  defp compare_value(actual, expected, :eq), do: actual == expected
  defp compare_value(actual, expected, :ne), do: actual != expected
  defp compare_value(actual, expected, :gt), do: actual > expected
  defp compare_value(actual, expected, :lt), do: actual < expected
  defp compare_value(actual, expected, :gte), do: actual >= expected
  defp compare_value(actual, expected, :lte), do: actual <= expected

  # ============================================================================
  # Command History Operations (via Recordings)
  # ============================================================================

  @doc """
  Lists command recordings for an organization/mission.

  Returns recordings with their loaded recordables for command-related events.

  ## Options

  - `:limit` - Max entries to return (default: 100)
  - `:organization_id` - Filter by organization
  - `:path_prefix` - Filter by bucket path prefix
  - `:bucket_id` - Filter by specific bucket
  """
  def list_command_history(opts \\ []) do
    Recordings.list_recordings_with_recordables(
      nil,
      Keyword.merge(opts, aggregate_types: ["Command"])
    )
  end

  @doc """
  Gets command history for a specific bucket.
  """
  def get_bucket_command_history(bucket_id, opts \\ []) do
    Recordings.list_aggregate_recordings("Command", nil,
      Keyword.merge(opts, bucket_id: bucket_id)
    )
  end

  # ============================================================================
  # Command Queue Operations
  # ============================================================================

  @doc """
  Enqueues a command for ordered execution.

  Commands are processed in priority order (0=emergency, 5=background)
  with FIFO ordering within the same priority level.

  ## Options

  - `:target` or `:target_id` - Target ID (required)
  - `:priority` - Priority level 0-5 (default: 3)
  - `:scheduled_at` - Execute at or after this time
  - `:expires_at` - Cancel if not executed by this time
  - `:max_attempts` - Max retry attempts (default: 3)
  - `:user_id` - User performing the action

  ## Returns

  - `{:ok, queue_entry}` - Command queued successfully
  - `{:error, reason}` - Enqueue failed

  ## Example

      {:ok, entry} = Commands.enqueue(mission_id, "SET_MODE", %{mode: 1},
        target: target_id,
        priority: 2
      )
  """
  @spec enqueue(String.t(), String.t(), map(), keyword()) ::
          {:ok, QueueEntry.t()} | {:error, term()}
  def enqueue(mission_id, command_name, params, opts \\ []) do
    target_id = get_target_id!(opts)
    TargetQueue.enqueue(mission_id, target_id, command_name, params, opts)
  end

  @doc """
  Pauses command dispatch for a specific target.

  Commands can still be enqueued but won't execute until resumed.
  Useful during anomaly handling or maintenance for a specific spacecraft.
  """
  @spec pause_target(String.t(), String.t()) :: :ok
  def pause_target(mission_id, target_id) do
    TargetDispatcher.pause(mission_id, target_id)
  end

  @doc """
  Resumes command dispatch for a specific target.
  """
  @spec resume_target(String.t(), String.t()) :: :ok
  def resume_target(mission_id, target_id) do
    TargetDispatcher.resume(mission_id, target_id)
  end

  @doc """
  Pauses command dispatch for all targets in a mission.

  Useful for mission-wide anomaly handling.
  """
  @spec pause_all_targets(String.t()) :: :ok
  def pause_all_targets(mission_id) do
    mission = Missions.get_mission!(mission_id)
    targets = Targets.list_targets(mission)

    Enum.each(targets, fn target ->
      TargetDispatcher.pause(mission_id, target.id)
    end)

    :ok
  end

  @doc """
  Resumes command dispatch for all targets in a mission.
  """
  @spec resume_all_targets(String.t()) :: :ok
  def resume_all_targets(mission_id) do
    mission = Missions.get_mission!(mission_id)
    targets = Targets.list_targets(mission)

    Enum.each(targets, fn target ->
      TargetDispatcher.resume(mission_id, target.id)
    end)

    :ok
  end

  @doc """
  Cancels a queued command by entry ID.

  Returns error if command is already executing or finished.
  """
  @spec cancel_queued(String.t(), String.t(), String.t()) ::
          {:ok, QueueEntry.t()} | {:error, :not_found | :already_finished | :currently_executing}
  def cancel_queued(mission_id, target_id, entry_id) do
    TargetQueue.cancel(mission_id, target_id, entry_id)
  end

  @doc """
  Cancels all pending commands for a specific target.

  Returns the number of cancelled entries.
  """
  @spec cancel_all_queued_for_target(String.t(), String.t()) :: {:ok, non_neg_integer()}
  def cancel_all_queued_for_target(mission_id, target_id) do
    TargetQueue.clear(mission_id, target_id)
  end

  @doc """
  Clears all pending commands from all targets in a mission.

  Returns the total number of cancelled entries.
  """
  @spec clear_all_queues(String.t()) :: {:ok, non_neg_integer()}
  def clear_all_queues(mission_id) do
    mission = Missions.get_mission!(mission_id)
    targets = Targets.list_targets(mission)

    total =
      Enum.reduce(targets, 0, fn target, acc ->
        {:ok, count} = TargetQueue.clear(mission_id, target.id)
        acc + count
      end)

    {:ok, total}
  end

  @doc """
  Gets the current status of a target's command queue/dispatcher.

  Returns a map with:
  - `:paused` - Whether the dispatcher is paused
  - `:pending` - Number of pending commands
  - `:executing` - Number of currently executing commands
  - `:failed` - Number of failed commands
  """
  @spec target_queue_status(String.t(), String.t()) :: map()
  def target_queue_status(mission_id, target_id) do
    queue_status = TargetQueue.status(mission_id, target_id)
    dispatcher_status = TargetDispatcher.status(mission_id, target_id)

    Map.merge(queue_status, %{paused: dispatcher_status.paused})
  end

  @doc """
  Lists pending commands in a target's queue.

  ## Options

  - `:limit` - Max entries to return (default: 100)
  """
  @spec list_target_queued(String.t(), String.t(), keyword()) :: [QueueEntry.t()]
  def list_target_queued(mission_id, target_id, opts \\ []) do
    TargetQueue.list_pending(mission_id, target_id, opts)
  end

  @doc """
  Changes the priority of a queued command.

  Higher priority commands (lower number) execute first.
  """
  @spec reorder_queued(String.t(), String.t(), String.t(), integer()) ::
          {:ok, QueueEntry.t()} | {:error, :not_found}
  def reorder_queued(mission_id, target_id, entry_id, new_priority) do
    TargetQueue.reorder(mission_id, target_id, entry_id, new_priority)
  end

  # ============================================================================
  # Fleet Operations
  # ============================================================================

  @doc """
  Dispatches the same command to multiple targets.

  Returns a list of {target_id, result} tuples.

  ## Example

      results = Commands.fleet_dispatch(mission_id, target_ids, "SAFE_MODE", %{})
      Enum.each(results, fn {target_id, result} ->
        case result do
          {:ok, cmd_id} -> Logger.info("Command sent to \#{target_id}")
          {:error, reason} -> Logger.error("Failed for \#{target_id}: \#{inspect(reason)}")
        end
      end)
  """
  @spec fleet_dispatch(String.t(), [String.t()], String.t(), map(), keyword()) ::
          [{String.t(), {:ok, String.t()} | {:error, term()}}]
  def fleet_dispatch(mission_id, target_ids, command_name, params, opts \\ []) do
    Enum.map(target_ids, fn target_id ->
      result = TargetDispatcher.dispatch(mission_id, target_id, command_name, params, opts)
      {target_id, result}
    end)
  end

  @doc """
  Enqueues the same command to multiple targets.

  Returns a list of {target_id, result} tuples.
  """
  @spec fleet_enqueue(String.t(), [String.t()], String.t(), map(), keyword()) ::
          [{String.t(), {:ok, QueueEntry.t()} | {:error, term()}}]
  def fleet_enqueue(mission_id, target_ids, command_name, params, opts \\ []) do
    Enum.map(target_ids, fn target_id ->
      result = TargetQueue.enqueue(mission_id, target_id, command_name, params, opts)
      {target_id, result}
    end)
  end

  @doc """
  Dispatches a command to multiple targets with per-target parameters.

  Each target can have unique parameter values, enabling operations like
  orbit adjustments where each satellite needs different values.

  ## Arguments

  - `mission_id` - The mission ID
  - `command_name` - Command to dispatch
  - `target_params` - List of `{target_id, params}` tuples
  - `opts` - Options applied to all dispatches

  ## Options

  - `:parallel` - Execute dispatches concurrently (default: false)
  - `:max_concurrency` - Max concurrent dispatches when parallel (default: 50)
  - `:timeout` - Timeout per dispatch in ms when parallel (default: 30_000)
  - Other options are passed through to each dispatch (e.g., `:user_id`)

  ## Returns

  Returns a list of `{target_id, result}` tuples in the same order as input.

  ## Examples

      # Sequential dispatch (default)
      results = Commands.fleet_dispatch_parameterized(
        mission_id,
        "SET_ORBIT",
        [
          {sat_001, %{altitude: 550.2, inclination: 53.01}},
          {sat_002, %{altitude: 550.5, inclination: 53.02}},
          {sat_003, %{altitude: 550.8, inclination: 53.03}}
        ],
        user_id: operator_id
      )

      # Parallel dispatch for large fleets
      results = Commands.fleet_dispatch_parameterized(
        mission_id,
        "POINTING_UPDATE",
        target_pointing_list,
        parallel: true,
        max_concurrency: 100
      )

      # Handle results
      Enum.each(results, fn
        {target_id, {:ok, cmd_id}} ->
          Logger.info("Command sent to \#{target_id}: \#{cmd_id}")
        {target_id, {:error, reason}} ->
          Logger.error("Failed for \#{target_id}: \#{inspect(reason)}")
      end)
  """
  @spec fleet_dispatch_parameterized(
          String.t(),
          String.t(),
          [{String.t(), map()}],
          keyword()
        ) :: [{String.t(), {:ok, String.t()} | {:error, term()}}]
  def fleet_dispatch_parameterized(mission_id, command_name, target_params, opts \\ [])

  def fleet_dispatch_parameterized(_mission_id, _command_name, [], _opts), do: []

  def fleet_dispatch_parameterized(mission_id, command_name, target_params, opts) do
    {parallel, dispatch_opts} = Keyword.pop(opts, :parallel, false)
    {max_concurrency, dispatch_opts} = Keyword.pop(dispatch_opts, :max_concurrency, 50)
    {timeout, dispatch_opts} = Keyword.pop(dispatch_opts, :timeout, 30_000)

    if parallel do
      dispatch_parameterized_parallel(
        mission_id,
        command_name,
        target_params,
        dispatch_opts,
        max_concurrency,
        timeout
      )
    else
      dispatch_parameterized_sequential(mission_id, command_name, target_params, dispatch_opts)
    end
  end

  defp dispatch_parameterized_sequential(mission_id, command_name, target_params, opts) do
    Enum.map(target_params, fn {target_id, params} ->
      result = TargetDispatcher.dispatch(mission_id, target_id, command_name, params, opts)
      {target_id, result}
    end)
  end

  defp dispatch_parameterized_parallel(
         mission_id,
         command_name,
         target_params,
         opts,
         max_concurrency,
         timeout
       ) do
    target_params
    |> Task.async_stream(
      fn {target_id, params} ->
        result = TargetDispatcher.dispatch(mission_id, target_id, command_name, params, opts)
        {target_id, result}
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {nil, {:error, :timeout}}
    end)
  end

  @doc """
  Enqueues a command to multiple targets with per-target parameters.

  Each target can have unique parameter values. Commands are queued
  for ordered execution according to priority and scheduling options.

  ## Arguments

  - `mission_id` - The mission ID
  - `command_name` - Command to enqueue
  - `target_params` - List of `{target_id, params}` tuples
  - `opts` - Options applied to all enqueues

  ## Options

  - `:parallel` - Execute enqueues concurrently (default: false)
  - `:max_concurrency` - Max concurrent enqueues when parallel (default: 50)
  - `:timeout` - Timeout per enqueue in ms when parallel (default: 30_000)
  - `:priority` - Priority level 0-5 for all commands (default: 3)
  - `:scheduled_at` - Execute at or after this time
  - `:expires_at` - Cancel if not executed by this time
  - Other options are passed through (e.g., `:user_id`)

  ## Returns

  Returns a list of `{target_id, result}` tuples in the same order as input.

  ## Examples

      # Enqueue firmware updates with per-satellite versions
      results = Commands.fleet_enqueue_parameterized(
        mission_id,
        "FIRMWARE_UPDATE",
        [
          {sat_001, %{version: "2.1.0", partition: "A"}},
          {sat_002, %{version: "2.1.0", partition: "B"}},
          {sat_003, %{version: "2.0.5", partition: "A"}}
        ],
        priority: 4,
        user_id: operator_id
      )

      # Parallel enqueue for large fleets
      results = Commands.fleet_enqueue_parameterized(
        mission_id,
        "CONFIG_UPDATE",
        target_config_list,
        parallel: true,
        priority: 3
      )
  """
  @spec fleet_enqueue_parameterized(
          String.t(),
          String.t(),
          [{String.t(), map()}],
          keyword()
        ) :: [{String.t(), {:ok, QueueEntry.t()} | {:error, term()}}]
  def fleet_enqueue_parameterized(mission_id, command_name, target_params, opts \\ [])

  def fleet_enqueue_parameterized(_mission_id, _command_name, [], _opts), do: []

  def fleet_enqueue_parameterized(mission_id, command_name, target_params, opts) do
    {parallel, enqueue_opts} = Keyword.pop(opts, :parallel, false)
    {max_concurrency, enqueue_opts} = Keyword.pop(enqueue_opts, :max_concurrency, 50)
    {timeout, enqueue_opts} = Keyword.pop(enqueue_opts, :timeout, 30_000)

    if parallel do
      enqueue_parameterized_parallel(
        mission_id,
        command_name,
        target_params,
        enqueue_opts,
        max_concurrency,
        timeout
      )
    else
      enqueue_parameterized_sequential(mission_id, command_name, target_params, enqueue_opts)
    end
  end

  defp enqueue_parameterized_sequential(mission_id, command_name, target_params, opts) do
    Enum.map(target_params, fn {target_id, params} ->
      result = TargetQueue.enqueue(mission_id, target_id, command_name, params, opts)
      {target_id, result}
    end)
  end

  defp enqueue_parameterized_parallel(
         mission_id,
         command_name,
         target_params,
         opts,
         max_concurrency,
         timeout
       ) do
    target_params
    |> Task.async_stream(
      fn {target_id, params} ->
        result = TargetQueue.enqueue(mission_id, target_id, command_name, params, opts)
        {target_id, result}
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {nil, {:error, :timeout}}
    end)
  end

  @doc """
  Starts a target's command pipeline.

  Called automatically when a target is created, but can be used to
  manually start a pipeline for a target.
  """
  @spec start_target_pipeline(String.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def start_target_pipeline(mission_id, target_id) do
    TargetPipelineSupervisor.start_pipeline(mission_id, target_id)
  end

  @doc """
  Stops a target's command pipeline.

  Called automatically when a target is deleted, but can be used to
  manually stop a pipeline for a target.
  """
  @spec stop_target_pipeline(String.t(), String.t()) :: :ok | {:error, :not_found}
  def stop_target_pipeline(mission_id, target_id) do
    TargetPipelineSupervisor.stop_pipeline(mission_id, target_id)
  end

  @doc """
  Gets a queue entry by ID.
  """
  @spec get_queue_entry(String.t()) :: QueueEntry.t() | nil
  def get_queue_entry(id) do
    Repo.get(QueueEntry, id)
  end

  @doc """
  Lists queue entries by status.

  ## Options

  - `:limit` - Max entries to return (default: 100)
  - `:status` - Filter by status (:pending, :executing, :completed, :failed, :cancelled, :expired)
  """
  @spec list_queue_entries(String.t(), keyword()) :: [QueueEntry.t()]
  def list_queue_entries(mission_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    status = Keyword.get(opts, :status)
    target_id = Keyword.get(opts, :target_id)
    preload = Keyword.get(opts, :preload, [])

    # Order by status (PG enum defines order: executing, pending, failed, completed, cancelled, expired),
    # then by command priority, then sequence number
    query =
      from(e in QueueEntry,
        where: e.mission_id == ^mission_id,
        order_by: [asc: e.status, asc: e.priority, asc: e.sequence_number],
        limit: ^limit
      )

    query =
      if status do
        statuses = List.wrap(status)
        from(e in query, where: e.status in ^statuses)
      else
        query
      end

    query =
      if target_id do
        from(e in query, where: e.target_id == ^target_id)
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Gets aggregated queue metrics for a mission.

  Returns counts by status, success rate, and total.
  """
  @spec get_mission_queue_metrics(String.t()) :: map()
  def get_mission_queue_metrics(mission_id) do
    # Get status counts
    status_counts =
      from(e in QueueEntry,
        where: e.mission_id == ^mission_id,
        group_by: e.status,
        select: {e.status, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    pending = Map.get(status_counts, :pending, 0)
    executing = Map.get(status_counts, :executing, 0)
    completed = Map.get(status_counts, :completed, 0)
    failed = Map.get(status_counts, :failed, 0)
    cancelled = Map.get(status_counts, :cancelled, 0)
    expired = Map.get(status_counts, :expired, 0)

    total_attempted = completed + failed
    success_rate = if total_attempted > 0, do: Float.round(completed / total_attempted * 100, 1), else: 100.0

    %{
      pending: pending,
      executing: executing,
      completed: completed,
      failed: failed,
      cancelled: cancelled,
      expired: expired,
      success_rate: success_rate,
      total_queued: pending + executing,
      total: pending + executing + completed + failed + cancelled + expired
    }
  end

  # ============================================================================
  # Command Staging Operations
  # ============================================================================

  @doc """
  Lists all staged commands for a mission.
  See `Cadence.Commands.Staging.list_staged/1`.
  """
  defdelegate list_staged(mission_id), to: Staging

  @doc """
  Gets a staged command by ID.
  See `Cadence.Commands.Staging.get_staged_command/1`.
  """
  defdelegate get_staged_command(id), to: Staging

  @doc """
  Gets a staged command by ID, raising if not found.
  See `Cadence.Commands.Staging.get_staged_command!/1`.
  """
  defdelegate get_staged_command!(id), to: Staging

  @doc """
  Gets a staged command target entry by ID.
  See `Cadence.Commands.Staging.get_target_entry/1`.
  """
  defdelegate get_staged_target_entry(id), to: Staging, as: :get_target_entry

  @doc """
  Adds a command to the staging area.
  See `Cadence.Commands.Staging.add_to_stage/5`.
  """
  defdelegate add_to_stage(user, mission_id, command, targets, opts \\ []), to: Staging

  @doc """
  Updates the parameters for a specific staged target entry.
  See `Cadence.Commands.Staging.update_target_params/2`.
  """
  defdelegate update_staged_target_params(entry_id, params), to: Staging, as: :update_target_params

  @doc """
  Updates the priority for a staged command.
  See `Cadence.Commands.Staging.update_priority/2`.
  """
  defdelegate update_staged_priority(id, priority), to: Staging, as: :update_priority

  @doc """
  Removes a specific target from a staged command.
  See `Cadence.Commands.Staging.remove_target/1`.
  """
  defdelegate remove_staged_target(entry_id), to: Staging, as: :remove_target

  @doc """
  Removes an entire staged command and all its targets.
  See `Cadence.Commands.Staging.remove_staged_command/1`.
  """
  defdelegate remove_staged_command(id), to: Staging

  @doc """
  Clears all staged commands for a mission.
  See `Cadence.Commands.Staging.clear_stage/1`.
  """
  defdelegate clear_stage(mission_id), to: Staging

  @doc """
  Queues a single target entry from staging.
  See `Cadence.Commands.Staging.queue_target/2`.
  """
  defdelegate queue_staged_target(entry_id, opts \\ []), to: Staging, as: :queue_target

  @doc """
  Queues all target entries from a single staged command.
  See `Cadence.Commands.Staging.queue_staged_command/2`.
  """
  defdelegate queue_staged_command(id, opts \\ []), to: Staging

  @doc """
  Queues all staged commands for a mission.
  See `Cadence.Commands.Staging.queue_all/2`.
  """
  defdelegate queue_all_staged(mission_id, opts \\ []), to: Staging, as: :queue_all

  @doc """
  Subscribes to staging changes for a mission.
  See `Cadence.Commands.Staging.subscribe/1`.
  """
  defdelegate subscribe_staging(mission_id), to: Staging, as: :subscribe

  @doc """
  Counts staged commands for a mission.
  See `Cadence.Commands.Staging.count_staged/1`.
  """
  defdelegate count_staged(mission_id), to: Staging

  @doc """
  Counts total target entries across all staged commands for a mission.
  See `Cadence.Commands.Staging.count_staged_targets/1`.
  """
  defdelegate count_staged_targets(mission_id), to: Staging

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_target_id!(opts) do
    case Keyword.get(opts, :target) || Keyword.get(opts, :target_id) do
      nil ->
        raise ArgumentError, "target or target_id is required in opts"

      target_id ->
        target_id
    end
  end
end
