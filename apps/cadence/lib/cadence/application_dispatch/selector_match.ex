defmodule Cadence.ApplicationDispatch.SelectorMatch do
  @moduledoc """
  Protocol-stage selector for governed application dispatch.
  """

  @type t :: %__MODULE__{
          packet_kind: atom() | nil,
          apid: non_neg_integer() | nil
        }

  defstruct [:packet_kind, :apid]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      packet_kind:
        attrs
        |> Map.get(:packet_kind, Map.get(attrs, "packet_kind"))
        |> normalize_packet_kind(),
      apid: Map.get(attrs, :apid, Map.get(attrs, "apid"))
    }
  end

  defp normalize_packet_kind(nil), do: nil
  defp normalize_packet_kind(packet_kind) when is_atom(packet_kind), do: packet_kind

  defp normalize_packet_kind(packet_kind) when is_binary(packet_kind),
    do: String.to_existing_atom(packet_kind)
end
