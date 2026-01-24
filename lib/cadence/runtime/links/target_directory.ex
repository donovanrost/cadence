defmodule Cadence.Runtime.Links.TargetDirectory do
  @moduledoc """
  Registry-backed lookup for target_id to ChannelId.
  """

  alias Cadence.Runtime.ChannelId

  @registry Cadence.MissionRegistry

  @spec register(String.t(), String.t(), ChannelId.t()) :: :ok
  def register(mission_id, target_id, %ChannelId{} = channel_id) do
    key = {:target_channel, mission_id, target_id}

    case Registry.lookup(@registry, key) do
      [] ->
        case Registry.register(@registry, key, [channel_id]) do
          {:ok, _} -> :ok
          {:error, {:already_registered, _}} -> update_channels(key, channel_id)
        end

      [{_pid, existing}] ->
        update_channels(key, channel_id, existing)
    end
  end

  @spec lookup(String.t(), String.t()) :: {:ok, ChannelId.t()} | {:error, :ambiguous} | :error
  def lookup(mission_id, target_id) do
    case list_channels(mission_id, target_id) do
      [] -> :error
      [channel_id] -> {:ok, channel_id}
      _ -> {:error, :ambiguous}
    end
  end

  @spec list_channels(String.t(), String.t()) :: [ChannelId.t()]
  def list_channels(mission_id, target_id) do
    case Registry.lookup(@registry, {:target_channel, mission_id, target_id}) do
      [{_pid, channels}] -> normalize_channels(channels)
      _ -> []
    end
  end

  defp update_channels(key, channel_id) do
    update_channels(key, channel_id, [])
  end

  defp update_channels(key, channel_id, existing) do
    Registry.update_value(@registry, key, fn _ ->
      existing
      |> normalize_channels()
      |> add_channel(channel_id)
    end)

    :ok
  end

  defp normalize_channels(%ChannelId{} = channel_id), do: [channel_id]
  defp normalize_channels(channels) when is_list(channels), do: channels
  defp normalize_channels(_), do: []

  defp add_channel(channels, %ChannelId{} = channel_id) do
    existing =
      channels
      |> Enum.reject(&(&1 == nil))
      |> Enum.uniq_by(&ChannelId.key/1)

    if Enum.any?(existing, &(ChannelId.key(&1) == ChannelId.key(channel_id))) do
      existing
    else
      existing ++ [channel_id]
    end
  end
end
