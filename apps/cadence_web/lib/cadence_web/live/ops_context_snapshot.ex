defmodule CadenceWeb.OpsContextSnapshot do
  @moduledoc """
  Ephemeral, mission-scoped operational context assembled for the shared Ops
  shell. It is a presentation read model built from canonical projections, not
  a second source of operational truth.
  """

  @type freshness :: :current | :stale | :unavailable

  @type context_module :: %{
          key: String.t(),
          title: String.t(),
          icon: String.t(),
          status: atom() | nil,
          count: non_neg_integer() | nil,
          freshness: freshness(),
          observed_at: DateTime.t(),
          destination: String.t(),
          data: term()
        }

  @type t :: %{
          mission_id: String.t(),
          observed_at: DateTime.t(),
          modules: [context_module()],
          pinned_focus: map() | nil
        }

  @module_order %{"alarms" => 0, "commands" => 1, "fleet_health" => 2}

  @spec new(String.t(), term(), DateTime.t()) :: t()
  def new(mission_id, fleet_health, observed_at \\ DateTime.utc_now())
      when is_binary(mission_id) and is_struct(observed_at, DateTime) do
    %{
      mission_id: mission_id,
      observed_at: observed_at,
      modules: [fleet_health_module(mission_id, fleet_health, observed_at)],
      pinned_focus: nil
    }
  end

  @spec put_fleet_health(t() | nil, String.t(), term(), DateTime.t()) :: t()
  def put_fleet_health(snapshot, mission_id, fleet_health, observed_at \\ DateTime.utc_now())
      when is_binary(mission_id) and is_struct(observed_at, DateTime) do
    snapshot = snapshot || new(mission_id, fleet_health, observed_at)
    fleet_health_module = fleet_health_module(mission_id, fleet_health, observed_at)

    snapshot
    |> Map.put(:mission_id, mission_id)
    |> Map.put(:observed_at, observed_at)
    |> Map.put_new(:pinned_focus, nil)
    |> put_module(fleet_health_module)
  end

  @spec put_alarm_summary(t(), map(), DateTime.t()) :: t()
  def put_alarm_summary(snapshot, summary, observed_at \\ DateTime.utc_now())
      when is_map(snapshot) and is_map(summary) and is_struct(observed_at, DateTime) do
    put_module(snapshot, %{
      key: "alarms",
      title: "Alarms",
      icon: "hero-bell-alert",
      status: Map.get(summary, :status),
      count: positive_or_nil(Map.get(summary, :active_count)),
      freshness: Map.get(summary, :freshness, :unavailable),
      observed_at: Map.get(summary, :observed_at) || observed_at,
      destination: "/missions/#{snapshot.mission_id}/ops/alarms",
      data: summary
    })
  end

  @spec put_command_summary(t(), map(), DateTime.t()) :: t()
  def put_command_summary(snapshot, summary, observed_at \\ DateTime.utc_now())
      when is_map(snapshot) and is_map(summary) and is_struct(observed_at, DateTime) do
    put_module(snapshot, %{
      key: "commands",
      title: "Commands",
      icon: "hero-command-line",
      status: Map.get(summary, :status),
      count: positive_or_nil(Map.get(summary, :active_count)),
      freshness: Map.get(summary, :freshness, :unavailable),
      observed_at: Map.get(summary, :observed_at) || observed_at,
      destination: "/missions/#{snapshot.mission_id}/ops/commands",
      data: summary
    })
  end

  @spec pin_command_focus(t(), String.t() | nil) :: t()
  def pin_command_focus(snapshot, command_request_id)
      when is_map(snapshot) and (is_binary(command_request_id) or is_nil(command_request_id)) do
    command_request_id = present_text(command_request_id)

    pinned_focus =
      if command_request_id do
        %{kind: :command, id: command_request_id}
      else
        nil
      end

    modules =
      Enum.map(snapshot.modules, fn context_module ->
        context_module
        |> Map.update!(:destination, &destination_with_focus(&1, command_request_id))
        |> maybe_put_followed_command(command_request_id)
      end)

    %{snapshot | pinned_focus: pinned_focus, modules: modules}
  end

  defp fleet_health_module(mission_id, fleet_health, observed_at) do
    %{
      key: "fleet_health",
      title: "Fleet health",
      icon: "hero-rocket-launch",
      status: fleet_health_status(fleet_health),
      count: fleet_health_violations(fleet_health),
      freshness: if(is_nil(fleet_health), do: :unavailable, else: :current),
      observed_at: observed_at,
      destination: "/missions/#{mission_id}",
      data: fleet_health
    }
  end

  defp put_module(snapshot, context_module) do
    modules =
      snapshot
      |> Map.get(:modules, [])
      |> Enum.reject(&(&1.key == context_module.key))
      |> then(&[context_module | &1])
      |> Enum.sort_by(&Map.get(@module_order, &1.key, 99))

    Map.put(snapshot, :modules, modules)
  end

  defp maybe_put_followed_command(%{key: "commands"} = context_module, command_request_id) do
    rows = get_in(context_module, [:data, :rows]) || []
    followed_command = Enum.find(rows, &(&1.command_request_id == command_request_id))
    put_in(context_module, [:data, :followed_command], followed_command)
  end

  defp maybe_put_followed_command(context_module, _command_request_id), do: context_module

  defp destination_with_focus(destination, command_request_id) do
    uri = URI.parse(destination)
    query = URI.decode_query(uri.query || "")

    query =
      if command_request_id do
        Map.put(query, "focus_command_id", command_request_id)
      else
        Map.delete(query, "focus_command_id")
      end

    %{uri | query: if(query == %{}, do: nil, else: URI.encode_query(query))}
    |> URI.to_string()
  end

  defp present_text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp present_text(_value), do: nil

  defp positive_or_nil(count) when is_integer(count) and count > 0, do: count
  defp positive_or_nil(_count), do: nil

  defp fleet_health_status(%{normalized_state_counts: %{red: red}}) when red > 0, do: :critical

  defp fleet_health_status(%{normalized_state_counts: %{yellow: yellow}}) when yellow > 0,
    do: :warning

  defp fleet_health_status(%{normalized_state_counts: _counts}), do: :nominal
  defp fleet_health_status(_fleet_health), do: nil

  defp fleet_health_violations(%{violating_points: count})
       when is_integer(count) and count > 0,
       do: count

  defp fleet_health_violations(_fleet_health), do: nil
end
