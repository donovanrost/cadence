defmodule Cadence.Contacts.ProviderClients.OutboundGuard do
  @moduledoc """
  The network boundary of every provider HTTP call (api-ops' security sweep, 11-15). A provider
  account's address is typed by an organization admin, so Cadence must not let it reach the
  platform's own network.

  - The host is resolved BEFORE connecting, and the request connects to the checked address
    (the original name only rides along for the Host header and TLS), so a name can't resolve
    to one address for the check and another for the connection.
  - Private, loopback, link-local (cloud metadata included), carrier-grade NAT, multicast and
    other reserved ranges are refused, unless this environment's configuration explicitly
    allows them (`config :cadence, :provider_outbound, allow: ["127.0.0.1/32"]` on dev for the
    simulator). There is no switch that turns the check off.
  - Redirects are never followed: a public address can't bounce the request inward.

  `{:error, {:outbound_address_denied, host}}` when refused; the request isn't sent and no
  credential leaves Cadence.
  """

  import Bitwise

  @denied_v4 [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @denied_v6 [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128},
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    {{0x0064, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96},
    {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64},
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @doc """
  `Req.request/1` behind the guard: resolves and checks the URL's host, then sends to the checked
  address with redirects off. Options: `:resolver` (`host -> {:ok, [ip]} | {:error, reason}`)
  and `:allow` (CIDR strings) override the defaults, for tests.
  """
  @spec request(keyword(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(req_opts, guard_opts \\ []) when is_list(req_opts) and is_list(guard_opts) do
    with {:ok, target} <- target(Keyword.fetch!(req_opts, :url), guard_opts) do
      req_opts
      |> Keyword.put(:url, target.url)
      |> Keyword.put(:redirect, false)
      |> Keyword.update(
        :connect_options,
        [hostname: target.hostname],
        &Keyword.put(&1, :hostname, target.hostname)
      )
      |> then(&Keyword.get(guard_opts, :send, fn opts -> Req.request(opts) end).(&1))
    end
  end

  @doc """
  The checked target for `url`: `{:ok, %{url, hostname, address}}` with `url` rewritten to the
  resolved address, or `{:error, {:outbound_address_denied, host}}` /
  `{:error, {:outbound_address_unresolved, host}}`.
  """
  @spec target(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def target(url, guard_opts \\ []) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        with {:ok, addresses} <- resolve(host, guard_opts),
             :ok <- all_allowed(addresses, host, allow(guard_opts)) do
          address = hd(addresses)

          {:ok,
           %{
             url: URI.to_string(%URI{uri | host: address_host(address)}),
             hostname: host,
             address: address
           }}
        end

      _other ->
        {:error, {:outbound_address_denied, url}}
    end
  end

  @doc "Whether `address` (an `:inet` tuple) is allowed under the CIDR strings `allow`."
  @spec allowed?(:inet.ip_address(), [binary()]) :: boolean()
  def allowed?(address, allow) when is_list(allow) do
    Enum.any?(allow, &in_cidr?(address, parse_cidr!(&1))) or not denied?(address)
  end

  defp all_allowed(addresses, host, allow) do
    if Enum.all?(addresses, &allowed?(&1, allow)),
      do: :ok,
      else: {:error, {:outbound_address_denied, host}}
  end

  defp resolve(host, guard_opts) do
    resolver = Keyword.get(guard_opts, :resolver, &resolve_dns/1)

    case resolver.(host) do
      {:ok, [_ | _] = addresses} -> {:ok, addresses}
      _unresolved -> {:error, {:outbound_address_unresolved, host}}
    end
  end

  defp resolve_dns(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, _not_literal} ->
        v4 = addresses(charlist, :inet)
        v6 = addresses(charlist, :inet6)
        if v4 ++ v6 == [], do: {:error, :nxdomain}, else: {:ok, v4 ++ v6}
    end
  end

  defp addresses(charlist, family) do
    case :inet.getaddrs(charlist, family) do
      {:ok, addresses} -> addresses
      {:error, _reason} -> []
    end
  end

  defp allow(guard_opts) do
    Keyword.get_lazy(guard_opts, :allow, fn ->
      :cadence |> Application.get_env(:provider_outbound, []) |> Keyword.get(:allow, [])
    end)
  end

  # An IPv4-mapped (::ffff:a.b.c.d) or NAT64 address is judged by the IPv4 address inside it.
  defp denied?({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: denied?(v4_of(high, low))
  defp denied?({0x0064, 0xFF9B, 0, 0, 0, 0, high, low}), do: denied?(v4_of(high, low))
  defp denied?({_, _, _, _} = v4), do: Enum.any?(@denied_v4, &in_cidr?(v4, &1))
  defp denied?({_, _, _, _, _, _, _, _} = v6), do: Enum.any?(@denied_v6, &in_cidr?(v6, &1))

  defp v4_of(high, low), do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp in_cidr?(address, {network, bits})
       when tuple_size(address) == tuple_size(network) do
    width = if tuple_size(address) == 4, do: 8, else: 16
    total = tuple_size(address) * width
    mask = bnot((1 <<< (total - bits)) - 1) &&& (1 <<< total) - 1
    (to_integer(address, width) &&& mask) == (to_integer(network, width) &&& mask)
  end

  defp in_cidr?(_address, _cidr), do: false

  defp to_integer(address, width),
    do: address |> Tuple.to_list() |> Enum.reduce(0, &(&2 <<< width ||| &1))

  defp parse_cidr!(cidr) do
    [address, bits] =
      case String.split(cidr, "/") do
        [address, bits] -> [address, bits]
        [address] -> [address, nil]
      end

    {:ok, parsed} = :inet.parse_address(String.to_charlist(address))
    max = if tuple_size(parsed) == 4, do: 32, else: 128
    {parsed, if(bits, do: String.to_integer(bits), else: max)}
  end

  defp address_host({_, _, _, _} = v4), do: v4 |> :inet.ntoa() |> to_string()
  # URI.to_string/1 brackets an IPv6 host itself.
  defp address_host(v6), do: v6 |> :inet.ntoa() |> to_string()
end
