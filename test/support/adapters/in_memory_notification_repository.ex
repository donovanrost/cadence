defmodule Cadence.Test.Adapters.InMemoryNotificationRepository do
  @moduledoc """
  In-memory notification repository for testing.

  Implements `Cadence.Ports.Repository.Notifications.NotificationRepository` behavior
  by storing notifications and preferences in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryNotificationRepository.start_link()
        Application.put_env(:cadence, :notification_repository, InMemoryNotificationRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :notification_repository)
          InMemoryNotificationRepository.stop()
        end)
        :ok
      end

      test "saves and finds a notification" do
        notification = %{id: nil, user_id: user_id, title: "Test", message: "Message"}
        {:ok, saved} = InMemoryNotificationRepository.save(notification)
        {:ok, found} = InMemoryNotificationRepository.find(saved.id, user_id)
        assert found.title == "Test"
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Notifications.NotificationRepository

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{notifications: %{}, preferences: %{}}
      end,
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
  # Notification Operations
  # ============================================================================

  @impl true
  def find(id, user_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.notifications, id) do
        nil -> {:error, :not_found}
        notification when notification.user_id == user_id -> {:ok, notification}
        _ -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def find_unscoped(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.notifications, id) end) do
      nil -> {:error, :not_found}
      notification -> {:ok, notification}
    end
  end

  @impl true
  def list(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    mission_id = Keyword.get(opts, :mission_id)
    unread_only = Keyword.get(opts, :unread_only, false)
    include_archived = Keyword.get(opts, :include_archived, false)

    Agent.get(__MODULE__, fn state ->
      state.notifications
      |> Map.values()
      |> Enum.filter(&(&1.user_id == user_id))
      |> filter_notifications(:mission_id, mission_id)
      |> filter_notifications(:unread_only, unread_only)
      |> filter_notifications(:include_archived, include_archived)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.drop(offset)
      |> Enum.take(limit)
    end)
  end

  @impl true
  def list_unread(user_id, opts \\ []) do
    list(user_id, Keyword.put(opts, :unread_only, true))
  end

  @impl true
  def count_unread(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    Agent.get(__MODULE__, fn state ->
      state.notifications
      |> Map.values()
      |> Enum.count(fn n ->
        n.user_id == user_id &&
          is_nil(n.read_at) &&
          is_nil(n.archived_at) &&
          (is_nil(mission_id) || n.mission_id == mission_id)
      end)
    end)
  end

  @impl true
  def save(notification) do
    notification =
      if Map.get(notification, :id) do
        notification
      else
        Map.put(notification, :id, Ecto.UUID.generate())
      end

    now = DateTime.utc_now()

    notification =
      notification
      |> maybe_set_field(:inserted_at, now)
      |> Map.put(:updated_at, now)

    Agent.update(__MODULE__, fn state ->
      %{state | notifications: Map.put(state.notifications, notification.id, notification)}
    end)

    {:ok, notification}
  end

  @impl true
  def save_batch(notifications) do
    results =
      Enum.map(notifications, fn notification ->
        {:ok, saved} = save(notification)
        saved
      end)

    {:ok, results}
  end

  @impl true
  def mark_read(notification) do
    updated = Map.put(notification, :read_at, DateTime.utc_now())

    Agent.update(__MODULE__, fn state ->
      %{state | notifications: Map.put(state.notifications, updated.id, updated)}
    end)

    {:ok, updated}
  end

  @impl true
  def mark_all_read(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    now = DateTime.utc_now()

    Agent.get_and_update(__MODULE__, fn state ->
      {updated_notifications, count} =
        state.notifications
        |> Enum.reduce({state.notifications, 0}, fn {id, notification}, acc ->
          mark_notification_read({id, notification}, user_id, mission_id, now, acc)
        end)

      {{:ok, count}, %{state | notifications: updated_notifications}}
    end)
  end

  defp mark_notification_read({id, notification}, user_id, mission_id, now, {acc, cnt}) do
    if unread_for_scope?(notification, user_id, mission_id) do
      updated = Map.put(notification, :read_at, now)
      {Map.put(acc, id, updated), cnt + 1}
    else
      {acc, cnt}
    end
  end

  defp unread_for_scope?(notification, user_id, mission_id) do
    notification.user_id == user_id &&
      is_nil(notification.read_at) &&
      is_nil(notification.archived_at) &&
      (is_nil(mission_id) || notification.mission_id == mission_id)
  end

  @impl true
  def archive(notification) do
    updated = Map.put(notification, :archived_at, DateTime.utc_now())

    Agent.update(__MODULE__, fn state ->
      %{state | notifications: Map.put(state.notifications, updated.id, updated)}
    end)

    {:ok, updated}
  end

  # ============================================================================
  # Notification Preference Operations
  # ============================================================================

  @impl true
  def find_preference(user_id, notification_type, mission_id) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.preferences
        |> Map.values()
        |> Enum.find(fn p ->
          p.user_id == user_id &&
            p.notification_type == notification_type &&
            p.mission_id == mission_id
        end)

      case result do
        nil -> {:error, :not_found}
        preference -> {:ok, preference}
      end
    end)
  end

  @impl true
  def save_preference(attrs) do
    user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")
    notification_type = Map.get(attrs, :notification_type) || Map.get(attrs, "notification_type")
    mission_id = Map.get(attrs, :mission_id) || Map.get(attrs, "mission_id")

    Agent.get_and_update(__MODULE__, fn state ->
      existing =
        state.preferences
        |> Map.values()
        |> Enum.find(fn p ->
          p.user_id == user_id &&
            p.notification_type == notification_type &&
            p.mission_id == mission_id
        end)

      now = DateTime.utc_now()

      preference =
        if existing do
          existing
          |> Map.merge(attrs)
          |> Map.put(:updated_at, now)
        else
          attrs
          |> Map.put(:id, Ecto.UUID.generate())
          |> Map.put(:user_id, user_id)
          |> Map.put(:notification_type, notification_type)
          |> Map.put(:mission_id, mission_id)
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end

      new_state = %{state | preferences: Map.put(state.preferences, preference.id, preference)}
      {{:ok, preference}, new_state}
    end)
  end

  @impl true
  def list_preferences(user_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    include_mission_prefs = Keyword.get(opts, :include_mission_prefs, true)

    Agent.get(__MODULE__, fn state ->
      state.preferences
      |> Map.values()
      |> Enum.filter(&(&1.user_id == user_id))
      |> filter_preferences(:mission_id, mission_id)
      |> filter_preferences(:include_mission_prefs, include_mission_prefs)
      |> Enum.sort_by(& &1.notification_type)
    end)
  end

  @impl true
  def delete_preference(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.preferences, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {preference, new_preferences} ->
          {{:ok, preference}, %{state | preferences: new_preferences}}
      end
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all notifications in the repository.
  """
  def all_notifications do
    Agent.get(__MODULE__, fn state -> Map.values(state.notifications) end)
  end

  @doc """
  Returns all preferences in the repository.
  """
  def all_preferences do
    Agent.get(__MODULE__, fn state -> Map.values(state.preferences) end)
  end

  @doc """
  Returns the count of notifications in the repository.
  """
  def notification_count do
    Agent.get(__MODULE__, fn state -> map_size(state.notifications) end)
  end

  @doc """
  Returns the count of preferences in the repository.
  """
  def preference_count do
    Agent.get(__MODULE__, fn state -> map_size(state.preferences) end)
  end

  @doc """
  Clears all entries from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{notifications: %{}, preferences: %{}} end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_set_field(map, field, value) do
    if Map.get(map, field) do
      map
    else
      Map.put(map, field, value)
    end
  end

  defp filter_notifications(notifications, _field, nil), do: notifications
  defp filter_notifications(notifications, :unread_only, false), do: notifications
  defp filter_notifications(notifications, :include_archived, true), do: notifications

  defp filter_notifications(notifications, :mission_id, mission_id) do
    Enum.filter(notifications, &(&1.mission_id == mission_id))
  end

  defp filter_notifications(notifications, :unread_only, true) do
    Enum.filter(notifications, &is_nil(&1.read_at))
  end

  defp filter_notifications(notifications, :include_archived, false) do
    Enum.filter(notifications, &is_nil(&1.archived_at))
  end

  defp filter_preferences(preferences, _field, nil), do: preferences
  defp filter_preferences(preferences, :include_mission_prefs, true), do: preferences

  defp filter_preferences(preferences, :mission_id, mission_id) do
    Enum.filter(preferences, &(&1.mission_id == mission_id))
  end

  defp filter_preferences(preferences, :include_mission_prefs, false) do
    Enum.filter(preferences, &is_nil(&1.mission_id))
  end
end
