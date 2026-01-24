defmodule Cadence.Runtime.Links.ProtocolConfig do
  @moduledoc """
  Normalizes protocol configuration for a link/interface into a runtime map.

  This keeps protocol config in the link layer (not in interface processes),
  while still allowing interface-specific protocol settings when needed.
  """

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Transport.COP1.Config, as: COP1Config

  @type t :: %{
          required(:interface_id) => String.t(),
          required(:cop1) => map(),
          required(:sdlp) => {:ok, %{mapping: term(), opts: keyword()}} | :error,
          required(:cop1_report_apids) => [non_neg_integer()]
        }

  @spec from_interface(Interface.t()) :: t()
  def from_interface(%Interface{} = interface) do
    cop1 = COP1Config.config(interface.config || %{})

    %{
      interface_id: interface.id,
      cop1: cop1,
      sdlp: SDLPConfig.fetch(interface),
      cop1_report_apids: report_apids_from_cop1(cop1)
    }
  end

  defp report_apids_from_cop1(config) when is_map(config) do
    apids = fetch_value(config, ["report_apids", :report_apids, "report_apid", :report_apid])

    normalize_apids(apids)
  end

  defp report_apids_from_cop1(_), do: []

  defp normalize_apids(nil), do: []

  defp normalize_apids(apids) when is_list(apids) do
    apids
    |> Enum.map(&parse_integer/1)
    |> Enum.filter(&is_integer/1)
  end

  defp normalize_apids(value) do
    case parse_integer(value) do
      nil -> []
      apid -> [apid]
    end
  end

  defp fetch_value(config, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(config, key) end)
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil
end
