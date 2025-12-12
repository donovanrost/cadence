defmodule Cadence.Commands do
  @moduledoc """
  Context module for managing spacecraft command definitions.

  Commands are part of the unified C&T database (DefinitionSet), versioned
  alongside telemetry packets. This context provides CRUD operations for
  command definitions and parameters.

  ## Safety Features

  Commands support safety metadata per ADR-004:

  - Hazardous command flagging
  - Operator confirmation requirements
  - Mission phase restrictions

  ## Example

      # List commands for a definition set
      commands = Commands.list_commands_for_definition_set(definition_set_id)

      # Get a specific command by name
      cmd = Commands.get_command_by_name(definition_set_id, "SAFE_MODE")

      # Validate command arguments
      :ok = Commands.validate_parameters(cmd, %{"target_temp" => 25.0})
  """

  import Ecto.Query

  alias Cadence.Repo

  alias Cadence.Commands.{
    CommandDefinition,
    CommandParameter,
    CommandLog,
    Dispatcher,
    Queue,
    QueueEntry
  }

  alias Cadence.Telemetry.CurrentValueTable

  # ============================================================================
  # Command Definition Operations
  # ============================================================================

  @doc """
  Creates a command definition.
  """
  def create_command(attrs) do
    %CommandDefinition{}
    |> CommandDefinition.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command definition.

  Note: Commands within a published DefinitionSet should be treated as immutable.
  Use this only for draft/unpublished definition sets.
  """
  def update_command(%CommandDefinition{} = command, attrs) do
    command
    |> CommandDefinition.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command definition and its parameters.
  """
  def delete_command(%CommandDefinition{} = command) do
    Repo.delete(command)
  end

  @doc """
  Gets a command definition by ID.
  """
  def get_command(id) do
    CommandDefinition
    |> Repo.get(id)
    |> Repo.preload(:command_parameters)
  end

  @doc """
  Gets a command definition by ID, raising if not found.
  """
  def get_command!(id) do
    CommandDefinition
    |> Repo.get!(id)
    |> Repo.preload(:command_parameters)
  end

  @doc """
  Gets a command definition by name for a DefinitionSet.
  """
  def get_command_by_name(definition_set_id, name) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      where: c.name == ^name,
      preload: :command_parameters,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a command definition by opcode for a DefinitionSet.
  """
  def get_command_by_opcode(definition_set_id, opcode) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      where: c.opcode == ^opcode,
      preload: :command_parameters,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all commands for a DefinitionSet.
  """
  def list_commands(definition_set_id) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      order_by: [asc: c.name],
      preload: :command_parameters
    )
    |> Repo.all()
  end

  @doc """
  Lists all commands for a specific DefinitionSet.
  Alias for list_commands/1.
  """
  def list_commands_for_definition_set(definition_set_id) do
    list_commands(definition_set_id)
  end

  @doc """
  Lists hazardous commands for a DefinitionSet.
  """
  def list_hazardous_commands(definition_set_id) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      where: c.is_hazardous == true,
      order_by: [asc: c.name],
      preload: :command_parameters
    )
    |> Repo.all()
  end

  @doc """
  Lists commands allowed in a specific mission phase.
  """
  def list_commands_for_phase(definition_set_id, phase) do
    list_commands(definition_set_id)
    |> Enum.filter(&CommandDefinition.allowed_in_phase?(&1, phase))
  end

  # ============================================================================
  # Command Parameter Operations
  # ============================================================================

  @doc """
  Creates a command parameter.
  """
  def create_parameter(attrs) do
    %CommandParameter{}
    |> CommandParameter.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command parameter.
  """
  def update_parameter(%CommandParameter{} = parameter, attrs) do
    parameter
    |> CommandParameter.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command parameter.
  """
  def delete_parameter(%CommandParameter{} = parameter) do
    Repo.delete(parameter)
  end

  @doc """
  Gets a command parameter by ID.
  """
  def get_parameter(id) do
    Repo.get(CommandParameter, id)
  end

  @doc """
  Lists parameters for a command, ordered by display_order.
  """
  def list_parameters(command_definition_id) do
    from(p in CommandParameter,
      where: p.command_definition_id == ^command_definition_id,
      order_by: [asc: p.display_order, asc: p.name]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validates command arguments against parameter definitions.

  Returns `:ok` if all validations pass, or `{:error, errors}` with a list
  of validation errors.

  ## Example

      case Commands.validate_parameters(command, %{"target_temp" => 25.0}) do
        :ok -> send_command(command, args)
        {:error, errors} -> handle_validation_errors(errors)
      end
  """
  def validate_parameters(%CommandDefinition{} = command, args) when is_map(args) do
    command = Repo.preload(command, :command_parameters)

    errors =
      command.command_parameters
      |> Enum.flat_map(fn param ->
        validate_single_parameter(param, args)
      end)

    # Check for unknown parameters
    known_names = MapSet.new(command.command_parameters, & &1.name)

    unknown_errors =
      args
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(known_names, to_string(&1)))
      |> Enum.map(fn name -> {name, "unknown parameter"} end)

    all_errors = errors ++ unknown_errors

    if Enum.empty?(all_errors) do
      :ok
    else
      {:error, all_errors}
    end
  end

  defp validate_single_parameter(%CommandParameter{} = param, args) do
    value = Map.get(args, param.name) || Map.get(args, String.to_atom(param.name))

    cond do
      # Required parameter missing
      CommandParameter.required?(param) && is_nil(value) ->
        [{param.name, "is required"}]

      # Optional parameter not provided - OK
      is_nil(value) ->
        []

      # Validate the provided value
      true ->
        case CommandParameter.validate_value(param, value) do
          :ok -> []
          {:error, reason} -> [{param.name, reason}]
        end
    end
  end

  # ============================================================================
  # Bulk Operations (for importers)
  # ============================================================================

  @doc """
  Creates a command definition with parameters in a single transaction.
  """
  def create_command_with_parameters(command_attrs, parameters_attrs) do
    Repo.transaction(fn ->
      case create_command(command_attrs) do
        {:ok, command} ->
          parameters =
            Enum.map(parameters_attrs, fn param_attrs ->
              param_attrs = Map.put(param_attrs, :command_definition_id, command.id)

              case create_parameter(param_attrs) do
                {:ok, param} -> param
                {:error, changeset} -> Repo.rollback({:parameter_error, changeset})
              end
            end)

          %{command | command_parameters: parameters}

        {:error, changeset} ->
          Repo.rollback({:command_error, changeset})
      end
    end)
  end

  @doc """
  Counts commands in a DefinitionSet.
  """
  def count_commands(definition_set_id) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      select: count(c.id)
    )
    |> Repo.one()
  end

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
  - `{:error, :validation_failed, errors}` - Parameter validation failed
  - `{:error, :not_allowed_in_phase, current_phase}` - Phase restriction
  - `{:error, :unknown_command}` - Command not found
  - `{:error, :unknown_target}` - Target not found
  - `{:error, :no_interface}` - No write interface for target
  - `{:error, :encoding_failed, reason}` - Binary encoding failed
  - `{:error, :send_failed, reason}` - Transmission failed

  ## Example

      {:ok, cmd_id} = Commands.dispatch(mission_id, "SET_MODE", %{mode: 1}, target: target_id)

      # Hazardous command
      {:error, :requires_confirmation, %{token: token}} = Commands.dispatch(mission_id, "SAFE_MODE", %{})
      {:ok, cmd_id} = Commands.confirm_dispatch(mission_id, token)
  """
  @spec dispatch(String.t(), String.t(), map(), keyword()) ::
          {:ok, String.t()}
          | {:error, atom()}
          | {:error, atom(), term()}
  def dispatch(mission_id, command_name, params, opts \\ []) do
    Dispatcher.dispatch(mission_id, command_name, params, opts)
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
  @spec confirm_dispatch(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def confirm_dispatch(mission_id, token) do
    Dispatcher.confirm_dispatch(mission_id, token)
  end

  @doc """
  Script-driven verification check.

  Waits for a CVT item to reach an expected value. This is used for explicit
  verification in scripts or procedures, as opposed to the automatic verification
  configured on CommandDefinition.

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
  # Command Log Operations
  # ============================================================================

  @doc """
  Gets a command log entry by ID.
  """
  def get_command_log(id) do
    Repo.get(CommandLog, id)
  end

  @doc """
  Lists command logs for a mission.

  ## Options

  - `:limit` - Max entries to return (default: 100)
  - `:status` - Filter by status
  - `:target_id` - Filter by target
  - `:command_name` - Filter by command name
  """
  def list_command_logs(mission_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(c in CommandLog,
        where: c.mission_id == ^mission_id,
        order_by: [desc: c.inserted_at],
        limit: ^limit
      )

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from(c in query, where: c.status == ^status)
      end

    query =
      case Keyword.get(opts, :target_id) do
        nil -> query
        target_id -> from(c in query, where: c.target_id == ^target_id)
      end

    query =
      case Keyword.get(opts, :command_name) do
        nil -> query
        name -> from(c in query, where: c.command_name == ^name)
      end

    Repo.all(query)
  end

  @doc """
  Gets command history for a specific target.
  """
  def get_target_command_history(target_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(c in CommandLog,
      where: c.target_id == ^target_id,
      order_by: [desc: c.sent_at],
      limit: ^limit
    )
    |> Repo.all()
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
  - `:immediate` - Skip queue, execute immediately (default: false)

  ## Returns

  - `{:ok, queue_entry}` - Command queued successfully
  - `{:ok, command_log_id}` - Command executed immediately (if :immediate)
  - `{:error, reason}` - Enqueue failed

  ## Example

      {:ok, entry} = Commands.enqueue(mission_id, "SET_MODE", %{mode: 1},
        target: target_id,
        priority: 2
      )
  """
  @spec enqueue(String.t(), String.t(), map(), keyword()) ::
          {:ok, QueueEntry.t()} | {:ok, String.t()} | {:error, term()}
  def enqueue(mission_id, command_name, params, opts \\ []) do
    Queue.enqueue(mission_id, command_name, params, opts)
  end

  @doc """
  Pauses command queue processing for a mission.

  Commands can still be enqueued but won't execute until resumed.
  Useful during anomaly handling or maintenance.
  """
  @spec pause_queue(String.t()) :: :ok
  def pause_queue(mission_id) do
    Queue.pause(mission_id)
  end

  @doc """
  Resumes command queue processing after a pause.
  """
  @spec resume_queue(String.t()) :: :ok
  def resume_queue(mission_id) do
    Queue.resume(mission_id)
  end

  @doc """
  Cancels a queued command by entry ID.

  Returns error if command is already executing or finished.
  """
  @spec cancel_queued(String.t(), String.t()) ::
          {:ok, QueueEntry.t()} | {:error, :not_found | :already_finished | :currently_executing}
  def cancel_queued(mission_id, entry_id) do
    Queue.cancel(mission_id, entry_id)
  end

  @doc """
  Cancels all pending commands for a specific target.

  Returns the number of cancelled entries.
  """
  @spec cancel_all_queued_for_target(String.t(), String.t()) :: {:ok, non_neg_integer()}
  def cancel_all_queued_for_target(mission_id, target_id) do
    Queue.cancel_all_for_target(mission_id, target_id)
  end

  @doc """
  Clears all pending commands from the mission's queue.

  Returns the number of cancelled entries.
  """
  @spec clear_queue(String.t()) :: {:ok, non_neg_integer()}
  def clear_queue(mission_id) do
    Queue.clear(mission_id)
  end

  @doc """
  Gets the current status of the command queue.

  Returns a map with:
  - `:paused` - Whether the queue is paused
  - `:pending` - Number of pending commands
  - `:executing` - Number of currently executing commands
  - `:failed` - Number of failed commands
  """
  @spec queue_status(String.t()) :: map()
  def queue_status(mission_id) do
    Queue.status(mission_id)
  end

  @doc """
  Lists pending commands in the queue.

  ## Options

  - `:limit` - Max entries to return (default: 100)
  - `:target_id` - Filter by target
  """
  @spec list_queued(String.t(), keyword()) :: [QueueEntry.t()]
  def list_queued(mission_id, opts \\ []) do
    Queue.list_pending(mission_id, opts)
  end

  @doc """
  Changes the priority of a queued command.

  Higher priority commands (lower number) execute first.
  """
  @spec reorder_queued(String.t(), String.t(), integer()) ::
          {:ok, QueueEntry.t()} | {:error, :not_found}
  def reorder_queued(mission_id, entry_id, new_priority) do
    Queue.reorder(mission_id, entry_id, new_priority)
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
    preload = Keyword.get(opts, :preload, [])

    query =
      from(e in QueueEntry,
        where: e.mission_id == ^mission_id,
        order_by: [desc: e.inserted_at],
        limit: ^limit
      )

    query =
      if status do
        statuses = List.wrap(status)
        from(e in query, where: e.status in ^statuses)
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(preload)
  end
end
