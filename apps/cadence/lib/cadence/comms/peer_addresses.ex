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
  @type invalid_allowlist :: :too_broad | :invalid

  @doc """
  Parses an allowlist: a list of entries, or one text with entries separated by commas or
  whitespace. `{:ok, normalized}` (each entry as `address/prefix`, sorted and unique) or
  `{:error, reason, message}` naming the first bad entry. An empty list is `{:ok, []}`.
  """
  @spec normalize(term()) :: {:ok, [binary()]} | {:error, invalid_allowlist(), binary()}
  def normalize(nil), do: {:ok, []}

  def normalize(text) when is_binary(text),
    do: text |> String.split([",", " ", "\n", "\t"], trim: true) |> normalize()

  def normalize(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case parse(entry) do
        {:ok, {_ip, 0}} ->
          {:halt, {:error, :too_broad, "#{inspect(entry)} allows every address."}}

        {:ok, range} ->
          {:cont, {:ok, [format(range) | acc]}}

        :error ->
          {:halt, {:error, :invalid, "#{inspect(entry)} is not an IP address or CIDR range."}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.uniq() |> Enum.sort()}
      error -> error
    end
  end

  def normalize(_other), do: {:error, :invalid, "Allowed source addresses must be a list."}

  @doc """
  What's wrong with an allowlist, as a stable reason: `:ok`, `:empty` (none given), `:too_broad`
  (an entry allows every address) or `:invalid` (an entry isn't an address or range).
  """
  @spec classify(term()) :: :ok | :empty | invalid_allowlist()
  def classify(entries) do
    case normalize(entries) do
      {:ok, []} -> :empty
      {:ok, _entries} -> :ok
      {:error, reason, _message} -> reason
    end
  end

  @doc """
  Parses normalized entries into ranges for `allowed?/2`. Unparseable entries, and any that would
  allow every address (a whole-family prefix), are dropped: the runtime never widens past what the
  save-time check accepts.
  """
  @spec ranges([binary()] | nil) :: [range()]
  def ranges(nil), do: []

  def ranges(entries) when is_list(entries) do
    for entry <- entries, {:ok, {_ip, length} = range} <- [parse(entry)], length > 0, do: range
  end

  @doc "Whether the peer address `ip` falls in any of `ranges`."
  @spec allowed?([range()], :inet.ip_address() | nil) :: boolean()
  def allowed?(_ranges, nil), do: false

  def allowed?(ranges, ip) when is_tuple(ip) do
    ip = unmap(ip)
    Enum.any?(ranges, &in_range?(&1, ip))
  end

  # An IPv4-mapped IPv6 range (::ffff:a.b.c.d/96..128) is the IPv4 range it maps, so
  # ::ffff:0:0/96 reads as 0.0.0.0/0 (every IPv4 address) and is refused like it. A wider IPv6
  # prefix over the mapped block stays IPv6. Every spelling of ::/0 parses to the same range.
  defp parse(entry) when is_binary(entry) do
    case String.split(String.trim(entry), "/", parts: 2) do
      [address] -> with {:ok, ip} <- address(address), do: {:ok, mapped({ip, bits(ip)})}
      [address, prefix] -> with {:ok, ip} <- address(address), do: prefix(ip, prefix)
    end
  end

  defp parse(_entry), do: :error

  defp address(text) do
    case :inet.parse_strict_address(String.to_charlist(text)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> :error
    end
  end

  defp mapped({{0, 0, 0, 0, 0, 0xFFFF, _high, _low} = ip, length}) when length >= 96,
    do: {unmap(ip), length - 96}

  defp mapped(range), do: range

  defp prefix(ip, text) do
    case Integer.parse(text) do
      {length, ""} when length >= 0 ->
        if length <= bits(ip), do: {:ok, mapped({ip, length})}, else: :error

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
