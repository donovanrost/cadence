defmodule Cadence.Runtime.Classifier.ConfigBased do
  @moduledoc """
  Config-driven classifier (placeholder).

  Intended seam for evolving to header-based classification.
  """

  @behaviour Cadence.Runtime.Classifier

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Telemetry.ConfigBundle

  @impl true
  def classify(organization_id, mission_id, transport_id, _bytes, metadata) do
    case metadata do
      %{channel_id: %ChannelId{} = channel_id} ->
        {:ok, channel_id}

      %{scid: scid, vcid: vcid} when is_integer(scid) and is_integer(vcid) ->
        {:ok, ChannelId.new(scid, vcid)}

      _ ->
        _organization_id = organization_id

        with {:ok, bundle} <- ConfigBundle.fetch(mission_id),
             [channel_id] <-
               bundle.bindings_by_transport
               |> Map.get(transport_id, [])
               |> Enum.uniq_by(&ChannelId.key/1) do
          {:ok, channel_id}
        else
          _ -> :ignore
        end
    end
  end
end
