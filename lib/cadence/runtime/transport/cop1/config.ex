defmodule Cadence.Runtime.Transport.COP1.Config do
  @moduledoc """
  COP-1 configuration parsing and routing policy.
  """

  alias Cadence.Domain.Interfaces.Entities.Interface

  @type cop1_mode :: :fop | :bypass

  @spec enabled?(Interface.t()) :: boolean()
  def enabled?(%Interface{} = interface) do
    interface.config
    |> config()
    |> mode()
    |> Kernel.==(:fop)
  end

  @spec mode_for(Interface.t(), atom() | nil, non_neg_integer() | nil) :: cop1_mode()
  def mode_for(%Interface{} = interface, pdu_type \\ nil, apid \\ nil) do
    cop1 = config(interface.config || %{})

    case mode(cop1) do
      :bypass -> :bypass
      :fop -> apply_apid_filter(cop1, pdu_type, apid)
    end
  end

  @spec mode_for_config(map(), atom() | nil, non_neg_integer() | nil) :: cop1_mode()
  def mode_for_config(cop1, pdu_type \\ nil, apid \\ nil) when is_map(cop1) do
    case mode(cop1) do
      :bypass -> :bypass
      :fop -> apply_apid_filter(cop1, pdu_type, apid)
    end
  end

  @spec config(map() | nil) :: map()
  def config(config) when is_map(config) do
    case fetch_value(config, ["cop1", :cop1]) do
      value when is_map(value) -> value
      "fop" -> %{"mode" => "fop"}
      :fop -> %{mode: :fop}
      _ -> %{}
    end
  end

  def config(_), do: %{}

  @spec mode(map()) :: cop1_mode()
  def mode(config) when is_map(config) do
    case fetch_value(config, ["mode", :mode]) do
      "fop" -> :fop
      :fop -> :fop
      "bypass" -> :bypass
      :bypass -> :bypass
      "disabled" -> :bypass
      :disabled -> :bypass
      _ -> if(fetch_value(config, ["enabled", :enabled]) == true, do: :fop, else: :bypass)
    end
  end

  def mode(_), do: :bypass

  defp apply_apid_filter(config, pdu_type, apid) do
    case apid_allowlist(config) do
      nil ->
        :fop

      [] ->
        :bypass

      apids ->
        if pdu_type == :space_packet and is_integer(apid) and Enum.member?(apids, apid) do
          :fop
        else
          :bypass
        end
    end
  end

  defp apid_allowlist(config) do
    case fetch_value(config, ["apids", :apids]) do
      nil ->
        nil

      apids when is_list(apids) ->
        apids
        |> Enum.map(&parse_integer/1)
        |> Enum.filter(&is_integer/1)

      value ->
        case parse_integer(value) do
          nil -> []
          apid -> [apid]
        end
    end
  end

  defp fetch_value(config, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(config, key) end)
  end

  defp fetch_value(config, key), do: Map.get(config, key)

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
