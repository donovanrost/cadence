defmodule Cadence.Test.Adapters.InMemoryProcedureRepository do
  @moduledoc """
  In-memory procedure repository for testing.

  Implements `Cadence.Ports.Repository.Procedures.ProcedureRepository` behavior
  by storing procedures and versions in an Agent, allowing tests to run without
  a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryProcedureRepository.start_link()
        Application.put_env(:cadence, :procedure_repository, InMemoryProcedureRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :procedure_repository)
          InMemoryProcedureRepository.stop()
        end)
        :ok
      end

      test "saves and finds a procedure version" do
        {:ok, version} = ProcedureVersion.new(valid_attrs())
        {:ok, saved} = InMemoryProcedureRepository.save_version(version)

        {:ok, found} = InMemoryProcedureRepository.find_version(saved.id)
        assert found.id == saved.id
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Procedures.ProcedureRepository

  alias Cadence.Domain.Procedures.Entities.ProcedureVersion

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn -> %{procedures: %{}, versions: %{}, version_numbers: %{}} end,
      name: name
    )
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
  # Procedure Operations
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.procedures, id) end) do
      nil -> {:error, :not_found}
      procedure -> {:ok, procedure}
    end
  end

  @impl true
  def find_by_slug(mission_id, slug) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.procedures
        |> Map.values()
        |> Enum.find(fn p -> p.mission_id == mission_id && p.slug == slug end)

      case result do
        nil -> {:error, :not_found}
        procedure -> {:ok, procedure}
      end
    end)
  end

  @impl true
  def save(procedure) do
    procedure =
      if procedure.id do
        procedure
      else
        Map.put(procedure, :id, Ecto.UUID.generate())
      end

    Agent.update(__MODULE__, fn state ->
      %{state | procedures: Map.put(state.procedures, procedure.id, procedure)}
    end)

    {:ok, procedure}
  end

  @impl true
  def list(mission_id, opts \\ []) do
    search = Keyword.get(opts, :search)
    category = Keyword.get(opts, :category)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      state.procedures
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
      |> filter_by_search(search)
      |> filter_by_category(category)
      |> Enum.drop(offset)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.procedures, id) do
        {nil, _} -> {{:error, :not_found}, state}
        {procedure, new_procedures} -> {{:ok, procedure}, %{state | procedures: new_procedures}}
      end
    end)
  end

  # ============================================================================
  # Version Operations
  # ============================================================================

  @impl true
  def find_version(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.versions, id) end) do
      nil -> {:error, :not_found}
      version -> {:ok, version}
    end
  end

  @impl true
  def save_version(version) do
    version =
      if version.id do
        version
      else
        Map.put(version, :id, Ecto.UUID.generate())
      end

    Agent.update(__MODULE__, fn state ->
      %{state | versions: Map.put(state.versions, version.id, version)}
    end)

    {:ok, version}
  end

  @impl true
  def list_versions(procedure_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)

    Agent.get(__MODULE__, fn state ->
      state.versions
      |> Map.values()
      |> Enum.filter(&(&1.procedure_id == procedure_id))
      |> filter_by_version_status(status_filter)
      |> Enum.sort_by(& &1.version_number, :desc)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def get_current_version(procedure_id) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.versions
        |> Map.values()
        |> Enum.filter(&(&1.procedure_id == procedure_id && &1.status == :approved))
        |> Enum.sort_by(& &1.version_number, :desc)
        |> List.first()

      case result do
        nil -> {:error, :not_found}
        version -> {:ok, version}
      end
    end)
  end

  # ============================================================================
  # Additional Operations (used by use cases)
  # ============================================================================

  @doc """
  Finds the approved version for a procedure.
  """
  def find_approved_version(procedure_id) do
    get_current_version(procedure_id)
  end

  @doc """
  Gets the next version number for a procedure.
  """
  def get_next_version_number(procedure_id) do
    Agent.get(__MODULE__, fn state ->
      versions =
        state.versions
        |> Map.values()
        |> Enum.filter(&(&1.procedure_id == procedure_id))

      case versions do
        [] -> 1
        vs -> (Enum.max_by(vs, & &1.version_number).version_number || 0) + 1
      end
    end)
  end

  @doc """
  Adds an approval to a version.
  """
  def add_approval(version_id, user_id, comment) do
    with {:ok, version} <- find_version(version_id) do
      ProcedureVersion.add_approval(version, user_id, comment)
    end
  end

  @doc """
  Deprecates all approved versions except the specified one.
  """
  def deprecate_other_versions(procedure_id, except_version_id) do
    Agent.update(__MODULE__, fn state ->
      new_versions =
        state.versions
        |> Enum.map(fn {id, version} ->
          if version.procedure_id == procedure_id &&
               version.id != except_version_id &&
               version.status == :approved do
            {id, %{version | status: :deprecated}}
          else
            {id, version}
          end
        end)
        |> Map.new()

      %{state | versions: new_versions}
    end)

    :ok
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all procedures in the repository.
  """
  def all_procedures do
    Agent.get(__MODULE__, fn state -> Map.values(state.procedures) end)
  end

  @doc """
  Returns all versions in the repository.
  """
  def all_versions do
    Agent.get(__MODULE__, fn state -> Map.values(state.versions) end)
  end

  @doc """
  Returns the count of procedures.
  """
  def procedure_count do
    Agent.get(__MODULE__, fn state -> map_size(state.procedures) end)
  end

  @doc """
  Returns the count of versions.
  """
  def version_count do
    Agent.get(__MODULE__, fn state -> map_size(state.versions) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ ->
      %{procedures: %{}, versions: %{}, version_numbers: %{}}
    end)
  end

  @doc """
  Inserts a version directly.
  """
  def insert_version(%ProcedureVersion{} = version) do
    version = if version.id, do: version, else: %{version | id: Ecto.UUID.generate()}

    Agent.update(__MODULE__, fn state ->
      %{state | versions: Map.put(state.versions, version.id, version)}
    end)

    version
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp filter_by_search(procedures, nil), do: procedures

  defp filter_by_search(procedures, search) do
    search_lower = String.downcase(search)

    Enum.filter(procedures, fn p ->
      String.contains?(String.downcase(p.name || ""), search_lower) ||
        String.contains?(String.downcase(p.description || ""), search_lower)
    end)
  end

  defp filter_by_category(procedures, nil), do: procedures

  defp filter_by_category(procedures, category) do
    Enum.filter(procedures, &(&1.category == category))
  end

  defp filter_by_version_status(versions, nil), do: versions

  defp filter_by_version_status(versions, statuses) when is_list(statuses) do
    Enum.filter(versions, &(&1.status in statuses))
  end

  defp filter_by_version_status(versions, status) when is_atom(status) do
    Enum.filter(versions, &(&1.status == status))
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
