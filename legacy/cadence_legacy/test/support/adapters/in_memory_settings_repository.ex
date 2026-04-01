defmodule Cadence.Test.Adapters.InMemorySettingsRepository do
  @moduledoc """
  In-memory settings repository for testing.

  Implements `Cadence.Ports.Repository.Settings.SettingsRepository` behavior
  by storing settings in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemorySettingsRepository.start_link()
        Application.put_env(:cadence, :settings_repository, InMemorySettingsRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :settings_repository)
          InMemorySettingsRepository.stop()
        end)
        :ok
      end

      test "stores a setting" do
        attrs = %{
          scope_id: Ecto.UUID.generate(),
          scope_type: "organization",
          namespace: "procedures",
          key: "required_approvals",
          value: %{"type" => "integer", "value" => 2}
        }
        {:ok, setting} = InMemorySettingsRepository.upsert(attrs)
        assert setting.value == %{"type" => "integer", "value" => 2}
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Settings.SettingsRepository

  alias Cadence.Settings.Setting

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{settings: %{}} end, name: name)
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
  # Setting Operations
  # ============================================================================

  @impl true
  def find(scope_id, scope_type, namespace, key) do
    composite_key = make_key(scope_id, scope_type, namespace, key)

    case Agent.get(__MODULE__, fn state -> Map.get(state.settings, composite_key) end) do
      nil -> {:error, :not_found}
      setting -> {:ok, setting}
    end
  end

  @impl true
  def get_value(scope_id, scope_type, namespace, key) do
    composite_key = make_key(scope_id, scope_type, namespace, key)

    Agent.get(__MODULE__, fn state ->
      case Map.get(state.settings, composite_key) do
        nil -> nil
        setting -> setting.value
      end
    end)
  end

  @impl true
  def list_by_scope(scope_id, scope_type, opts \\ []) do
    namespace_filter = Keyword.get(opts, :namespace)

    Agent.get(__MODULE__, fn state ->
      state.settings
      |> Map.values()
      |> Enum.filter(fn setting ->
        setting.scope_id == scope_id &&
          setting.scope_type == scope_type &&
          (is_nil(namespace_filter) || setting.namespace == to_string(namespace_filter))
      end)
      |> Enum.sort_by(&{&1.namespace, &1.key})
    end)
  end

  @impl true
  def upsert(attrs) do
    scope_id = Map.get(attrs, :scope_id) || Map.get(attrs, "scope_id")
    scope_type = Map.get(attrs, :scope_type) || Map.get(attrs, "scope_type")
    namespace = to_string(Map.get(attrs, :namespace) || Map.get(attrs, "namespace"))
    key = to_string(Map.get(attrs, :key) || Map.get(attrs, "key"))
    value = Map.get(attrs, :value) || Map.get(attrs, "value")

    composite_key = make_key(scope_id, scope_type, namespace, key)

    Agent.get_and_update(__MODULE__, fn state ->
      existing = Map.get(state.settings, composite_key)
      now = DateTime.utc_now()

      setting =
        if existing do
          %{existing | value: value, updated_at: now}
        else
          %Setting{
            id: Ecto.UUID.generate(),
            scope_id: scope_id,
            scope_type: scope_type,
            namespace: namespace,
            key: key,
            value: value,
            inserted_at: now,
            updated_at: now
          }
        end

      new_state = %{state | settings: Map.put(state.settings, composite_key, setting)}
      {{:ok, setting}, new_state}
    end)
  end

  @impl true
  def delete(scope_id, scope_type, namespace, key) do
    composite_key = make_key(scope_id, scope_type, namespace, key)

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.settings, composite_key) do
        {nil, _state} -> {{:ok, 0}, state}
        {_setting, new_settings} -> {{:ok, 1}, %{state | settings: new_settings}}
      end
    end)
  end

  @impl true
  def delete_all_for_scope(scope_id, scope_type) do
    Agent.get_and_update(__MODULE__, fn state ->
      {to_delete, to_keep} =
        state.settings
        |> Map.split_with(fn {_key, setting} ->
          setting.scope_id == scope_id && setting.scope_type == scope_type
        end)

      count = map_size(to_delete)
      {{:ok, count}, %{state | settings: to_keep}}
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all settings in the repository.
  """
  def all_settings do
    Agent.get(__MODULE__, fn state -> Map.values(state.settings) end)
  end

  @doc """
  Returns the count of settings in the repository.
  """
  def setting_count do
    Agent.get(__MODULE__, fn state -> map_size(state.settings) end)
  end

  @doc """
  Clears all entries from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{settings: %{}} end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp make_key(scope_id, scope_type, namespace, key) do
    {scope_id, scope_type, to_string(namespace), to_string(key)}
  end
end
