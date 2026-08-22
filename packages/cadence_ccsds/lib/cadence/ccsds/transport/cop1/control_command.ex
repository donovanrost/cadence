defmodule Cadence.CCSDS.Transport.COP1.ControlCommand do
  @moduledoc """
  Codec for the two COP-1 control commands carried by Type-BC TC frames.

  Unlock is encoded as one zero octet. Set V(R) is encoded as `82 00 VV`,
  where `VV` is the next Type-AD frame sequence number expected by FARM-1.
  """

  @type t :: :unlock | {:set_vr, 0..255}

  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(:unlock), do: {:ok, <<0>>}

  def encode({:set_vr, receiver_frame_sequence_number})
      when is_integer(receiver_frame_sequence_number) and
             receiver_frame_sequence_number in 0..255 do
    {:ok, <<0x82, 0, receiver_frame_sequence_number>>}
  end

  def encode({:set_vr, receiver_frame_sequence_number}),
    do: {:error, {:invalid_receiver_frame_sequence_number, receiver_frame_sequence_number}}

  def encode(command), do: {:error, {:invalid_control_command, command}}

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(<<0>>), do: {:ok, :unlock}

  def decode(<<0x82, 0, receiver_frame_sequence_number>>),
    do: {:ok, {:set_vr, receiver_frame_sequence_number}}

  def decode(octets) when is_binary(octets), do: {:error, {:invalid_control_command, octets}}
end
