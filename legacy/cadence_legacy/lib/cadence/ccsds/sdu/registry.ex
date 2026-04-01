defmodule Cadence.CCSDS.SDU.Registry do
  @moduledoc """
  Registry for SDU codecs.
  """

  alias Cadence.CCSDS.Custom.SchemaRegistry
  alias Cadence.CCSDS.SDU.EncapCodec
  alias Cadence.CCSDS.SDU.SpacePacketCodec

  @type sdu_type :: :space_packet | :encap | {:custom, String.t(), pos_integer()}

  @spec fetch(sdu_type()) :: {:ok, module()} | :error
  def fetch(:space_packet), do: {:ok, SpacePacketCodec}
  def fetch(:encap), do: {:ok, EncapCodec}

  def fetch({:custom, name, version}), do: SchemaRegistry.fetch(name, version)

  def fetch(_), do: :error
end
