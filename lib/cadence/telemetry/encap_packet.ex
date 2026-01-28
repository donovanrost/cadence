defmodule Cadence.Telemetry.EncapPacket do
  @moduledoc """
  Minimal encapsulation packet representation (stub).
  """

  @type t :: %__MODULE__{
          header: map(),
          payload: binary(),
          raw_ref: map() | nil
        }

  defstruct [:header, :payload, :raw_ref]

  @spec parse(binary()) ::
          {:ok, t()} | {:error, term()} | {:unknown, Cadence.Telemetry.UnknownUnit.t()}
  def parse(raw) when is_binary(raw) do
    {:unknown,
     %Cadence.Telemetry.UnknownUnit{reason: :encap_not_supported, raw: raw, context: %{}}}
  end
end
