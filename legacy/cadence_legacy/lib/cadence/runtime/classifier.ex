defmodule Cadence.Runtime.Classifier do
  @moduledoc """
  Mission-level downlink classifier behavior.

  This is intentionally not interface-owned to keep protocol state keyed by ChannelId.
  """

  alias Cadence.Runtime.ChannelId

  @callback classify(String.t(), String.t(), String.t(), binary(), map()) ::
              {:ok, ChannelId.t()} | :ignore

  @spec classify(String.t(), String.t(), String.t(), binary(), map()) ::
          {:ok, ChannelId.t()} | :ignore
  def classify(organization_id, mission_id, transport_id, bytes, metadata) do
    impl().classify(organization_id, mission_id, transport_id, bytes, metadata)
  end

  defp impl do
    Application.get_env(:cadence, :classifier_impl, Cadence.Runtime.Classifier.ConfigBased)
  end
end
