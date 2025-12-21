defmodule Cadence.Test.Adapters.InMemoryCommandsRepository do
  @moduledoc """
  In-memory commands repository for testing.

  Implements `Cadence.Ports.Repository.Commanding.CommandsRepository` behavior
  by storing MetaCommands in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryCommandsRepository.start_link()
        Application.put_env(:cadence, :commands_repository, InMemoryCommandsRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :commands_repository)
          InMemoryCommandsRepository.stop()
        end)
        :ok
      end

      test "finds a command by name" do
        command = %{id: Ecto.UUID.generate(), name: "POWER_ON", definition_set_id: set_id}
        {:ok, _} = InMemoryCommandsRepository.save(command)
        {:ok, found} = InMemoryCommandsRepository.find_by_name(set_id, "POWER_ON")
        assert found.name == "POWER_ON"
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Commanding.CommandsRepository

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{commands: %{}} end, name: name)
  end

  def stop(pid \\ __MODULE__) do
    try do
      Agent.stop(pid)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  # ============================================================================
  # CommandsRepository Implementation
  # ============================================================================

  @impl true
  def find_by_name(definition_set_id, name) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.commands
        |> Map.values()
        |> Enum.find(fn c ->
          c.definition_set_id == definition_set_id && c.name == name
        end)

      case result do
        nil -> {:error, :not_found}
        command -> {:ok, command}
      end
    end)
  end

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.commands, id) end) do
      nil -> {:error, :not_found}
      command -> {:ok, command}
    end
  end

  @impl true
  def find_by_opcode(definition_set_id, opcode) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.commands
        |> Map.values()
        |> Enum.find(fn c ->
          c.definition_set_id == definition_set_id && c.opcode == opcode
        end)

      case result do
        nil -> {:error, :not_found}
        command -> {:ok, command}
      end
    end)
  end

  @impl true
  def list(definition_set_id, opts \\ []) do
    include_abstract = Keyword.get(opts, :include_abstract, false)

    Agent.get(__MODULE__, fn state ->
      state.commands
      |> Map.values()
      |> Enum.filter(fn c ->
        c.definition_set_id == definition_set_id &&
          (include_abstract || !Map.get(c, :abstract, false))
      end)
      |> Enum.sort_by(& &1.name)
    end)
  end

  @impl true
  def list_hazardous(definition_set_id) do
    Agent.get(__MODULE__, fn state ->
      state.commands
      |> Map.values()
      |> Enum.filter(fn c ->
        c.definition_set_id == definition_set_id &&
          Map.get(c, :is_hazardous, false) == true
      end)
      |> Enum.sort_by(& &1.name)
    end)
  end

  @impl true
  def count(definition_set_id) do
    Agent.get(__MODULE__, fn state ->
      state.commands
      |> Map.values()
      |> Enum.count(fn c ->
        c.definition_set_id == definition_set_id &&
          !Map.get(c, :abstract, false)
      end)
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Saves a command to the repository.
  """
  def save(command) do
    command =
      if command.id do
        command
      else
        Map.put(command, :id, Ecto.UUID.generate())
      end

    Agent.update(__MODULE__, fn state ->
      %{state | commands: Map.put(state.commands, command.id, command)}
    end)

    {:ok, command}
  end

  @doc """
  Returns all commands in the repository.
  """
  def all_commands do
    Agent.get(__MODULE__, fn state -> Map.values(state.commands) end)
  end

  @doc """
  Returns the count of commands in the repository.
  """
  def command_count do
    Agent.get(__MODULE__, fn state -> map_size(state.commands) end)
  end

  @doc """
  Clears all entries from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{commands: %{}} end)
  end
end
