defmodule Cadence.Runtime.Uplink.Resolver do
  @moduledoc """
  Resolves target_id to ChannelId via config bundle channel_targets.
  """

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Telemetry.ConfigBundle

  @spec list_channels(String.t(), String.t(), String.t()) :: [ChannelId.t()]
  def list_channels(organization_id, mission_id, target_id) do
    _organization_id = organization_id

    case ConfigBundle.fetch(mission_id) do
      {:ok, bundle} ->
        Map.get(bundle.channels_by_target, target_id, [])

      {:error, _} ->
        []
    end
  end
end
