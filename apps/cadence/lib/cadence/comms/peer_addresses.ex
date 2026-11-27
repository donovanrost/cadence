defmodule Cadence.Comms.PeerAddresses do
  @moduledoc """
  A listen endpoint's source allowlist (#990, DECISIONS #115): the addresses a provider may
  connect from, as IPv4 or IPv6 addresses or CIDR ranges.

  A listening transport carries the list (`expected_peer_addresses`) and its materialized provider
  profile passes it to the runtime, which refuses any peer outside it before reading a frame. The
  same parsing serves the save-time check (the transport kind) and the runtime match, so the two
  never disagree on what an entry means. An IPv4-mapped IPv6 peer (`::ffff:a.b.c.d`) matches as
  its IPv4 address.
  """

  import Bitwise

  @type range :: {:inet.ip_address(), non_neg_integer()}

  @doc """
  Parses an allowlist: a list of entries, or one text with entries separated by commas or
  whitespace. `{:ok, normalized}` (each entry as `address/prefix`, sorted and unique) or
  `{:error, message}` naming the first bad entry. An empty list is `{:ok, []}`.
  """
  @spec normalize(term()) :: {:ok, [binary()]} | {:error, binary()}
  def normalize(nil), do: {:ok, []}

  def normalize(text) when is_binary(text),
    do: text |> String.split([",", " ", "\n", "\t"], trim: true) |> normalize()

  def normalize(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case parse(entry) do
        {:ok, range} -> {:cont, {:ok, [format(range) | acc]}}
        :error -> {:halt, {:error, "#{inspect(entry)} is not an IP address or CIDR range."}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.uniq() |> Enum.sort()}
      error -> error
    end
  end

  def normalize(_other), do: {:error, "Allowed source addresses must be a list."}

  @doc "Parses normalized entries into ranges for `allowed?/2` (unparseable entries are dropped)."
  @spec ranges([binary()] | nil) :: [range()]
  def ranges(nil), do: []

  def ranges(entries) when is_list(entries) do
    for entry <- entries, {:ok, range} <- [parse(entry)], do: range
  end

  @doc "Whether the peer address `ip` falls in any of `ranges`."
  @spec allowed?([range()], :inet.ip_address() | nil) :: boolean()
  def allowed?(_ranges, nil), do: false

  def allowed?(ranges, ip) when is_tuple(ip) do
    ip = unmap(ip)
    Enum.any?(ranges, &in_range?(&1, ip))
  end

  defp parse(entry) when is_binary(entry) do
    case String.split(String.trim(entry), "/", parts: 2) do
      [address] -> with {:ok, ip} <- address(address), do: {:ok, {ip, bits(ip)}}
      [address, prefix] -> with {:ok, ip} <- address(address), do: prefix(ip, prefix)
    end
  end

  defp parse(_entry), do: :error

  defp address(text) do
    case :inet.parse_strict_address(String.to_charlist(text)) do
      {:ok, ip} -> {:ok, unmap(ip)}
      {:error, _reason} -> :error
    end
  end

  defp prefix(ip, text) do
    case Integer.parse(text) do
      {length, ""} when length >= 0 ->
        if length <= bits(ip), do: {:ok, {ip, length}}, else: :error

      _other ->
        :error
    end
  end

  defp format({ip, length}), do: "#{:inet.ntoa(mask(ip, length))}/#{length}"

  defp in_range?({network, length}, ip),
    do: tuple_size(network) == tuple_size(ip) and mask(ip, length) == mask(network, length)

  defp mask(ip, length) do
    total = bits(ip)
    width = div(total, tuple_size(ip))
    value = ip |> Tuple.to_list() |> Enum.reduce(0, &(&2 <<< width ||| &1))
    masked = value &&& ((1 <<< length) - 1) <<< (total - length)

    (tuple_size(ip) - 1)..0//-1
    |> Enum.map(&(masked >>> (&1 * width) &&& (1 <<< width) - 1))
    |> List.to_tuple()
  end

  defp bits(ip) when tuple_size(ip) == 4, do: 32
  defp bits(ip) when tuple_size(ip) == 8, do: 128

  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp unmap(ip), do: ip
end
