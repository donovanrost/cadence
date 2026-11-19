defmodule CadenceWeb.Console.ConfigLive do
  @moduledoc """
  Change-set live relays for `CadenceWeb.Console.MissionChannel`:
  `config_runtime` (from the mission's runtime topic) and `change_set_progress`
  (from the open change set's progress topic, re-subscribed whenever the
  mission's configuration changes so it follows the current set).
  """

  alias Cadence.Control.Configuration
  alias CadenceWeb.Console.ConfigJSON
  alias Phoenix.Socket

  @pubsub Cadence.PubSub

  @spec join(Socket.t()) :: Socket.t()
  def join(socket) do
    %{organization_id: org, mission_id: mission} = socket.assigns
    :ok = Phoenix.PubSub.subscribe(@pubsub, Configuration.runtime_topic(org, mission))

    socket
    |> Socket.assign(:progress_set_id, nil)
    |> follow_current_set()
  end

  @doc "Moves the progress subscription to the mission's current change set, if it changed."
  @spec follow_current_set(Socket.t()) :: Socket.t()
  def follow_current_set(socket) do
    current_id =
      case Configuration.current(socket.assigns.scope, socket.assigns.mission_id) do
        {:ok, %{change_set: %{id: id}}} -> id
        _none -> nil
      end

    case socket.assigns.progress_set_id do
      ^current_id ->
        socket

      previous ->
        if previous,
          do: Phoenix.PubSub.unsubscribe(@pubsub, Configuration.progress_topic(previous))

        if current_id,
          do: Phoenix.PubSub.subscribe(@pubsub, Configuration.progress_topic(current_id))

        Socket.assign(socket, :progress_set_id, current_id)
    end
  end

  @spec progress_payload(binary(), map()) :: map()
  def progress_payload(set_id, step),
    do: Map.put(ConfigJSON.encode(step), "change_set_id", set_id)

  @spec runtime_payload(map()) :: map()
  def runtime_payload(runtime), do: ConfigJSON.encode(runtime)
end
