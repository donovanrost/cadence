defmodule Cadence.Contacts.ProviderClients.OutboundGuard do
  @moduledoc """
  The network boundary of every provider HTTP call (api-ops' security sweep, 11-15). A provider
  account's address is typed by an organization admin, so Cadence must not let it reach the
  platform's own network.

  - The host is resolved BEFORE connecting, and the request connects to the checked address
    (the original name only rides along for the Host header, SNI and certificate verification,
    via Mint's `:hostname`), so a name can't resolve to one address for the check and another for
    the connection. Any refused answer refuses the call.
  - Private, loopback, link-local (cloud metadata included), carrier-grade NAT, documentation,
    multicast and other reserved ranges are refused, IPv6 forms that embed or translate IPv4
    included, unless this environment's configuration explicitly allows a range
    (`config :cadence, :provider_outbound, allow: ["127.0.0.1/32"]` on dev for the simulator;
    `CADENCE_PROVIDER_OUTBOUND_ALLOW` for a deployment). The allowlist is validated at boot
    (`validate_config!/0`): no range wider than /8 (IPv4) or /32 (IPv6), and link-local and
    metadata addresses can never be allowed. There is no switch that turns the check off.
  - Redirects are never followed: a public address can't bounce the request inward.
  - The transport is injectable only BEHIND the guard (`:send`): a caller can replace how a
    checked request is sent, never skip the check.

  Req starts one Finch pool per distinct `connect_options`, so one pool per provider host name;
  fine at this scale.

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
    {{192, 88, 99, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @denied_v6 [
    # ::/96 IPv4-compatible (with :: and ::1).
    {{0, 0, 0, 0, 0, 0, 0, 0}, 96},
    # ::ffff:0:0:0/96 IPv4-translated (::ffff:0:a.b.c.d).
    {{0, 0, 0, 0, 0xFFFF, 0, 0, 0}, 96},
    # 64:ff9b:1::/48 local-use NAT64 (RFC 8215).
    {{0x0064, 0xFF9B, 0x0001, 0, 0, 0, 0, 0}, 48},
    {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64},
    # 6to4 (2002::/16) embeds IPv4; refused outright, as is Teredo below.
    # 2001::/23 IETF protocol assignments (Teredo's 2001::/32 included).
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23},
    # 3fff::/20 documentation (RFC 9637) and 5f00::/16 SRv6 SIDs.
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20},
    {{0x5F00, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  # Never allowable, whatever an allowlist says: link-local (cloud metadata lives there) and the
  # IPv6 metadata address.
  @never_allowed [
    {{169, 254, 0, 0}, 16},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFD00, 0x0EC2, 0, 0, 0, 0, 0, 0x0254}, 128}
  ]

  # IPv6 ranges that carry IPv4 addresses. An allow entry may not fall in one: the operator
  # names the IPv4 range itself (api: '::ffff:0:0/96' would otherwise re-allow all of IPv4).
  @v4_embedding [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 96},
    {{0, 0, 0, 0, 0, 0xFFFF, 0, 0}, 96},
    {{0, 0, 0, 0, 0xFFFF, 0, 0, 0}, 96},
    {{0x0064, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96},
    {{0x0064, 0xFF9B, 0x0001, 0, 0, 0, 0, 0}, 48},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 32}
  ]

  @min_prefix %{4 => 8, 8 => 32}

  @doc """
  `Req.request/1` behind the guard: resolves and checks the URL's host, then sends to the checked
  address with redirects off. Options: `:send` (how a CHECKED request is sent; `Req.request/1`
  by default), and for tests `:resolver` (`host -> {:ok, [ip]} | {:error, reason}`) and `:allow`
  (CIDR strings, validated like the configuration).
  """
  @spec request(keyword(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(req_opts, guard_opts \\ []) when is_list(req_opts) and is_list(guard_opts) do
    send_fun = Keyword.get(guard_opts, :send) || (&Req.request/1)

    with {:ok, target} <- target(Keyword.fetch!(req_opts, :url), guard_opts) do
      req_opts
      |> Keyword.put(:url, target.url)
      |> Keyword.put(:redirect, false)
      |> Keyword.update(
        :connect_options,
        [hostname: target.hostname],
        &Keyword.put(&1, :hostname, target.hostname)
      )
      |> send_fun.()
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
        {:error, {:outbound_address_denied, :unsupported_url}}
    end
  end

  @doc """
  Whether `address` (an `:inet` tuple) may be called under the parsed allowlist `allow`
  (`parse_allow!/1`). Link-local and metadata addresses never are.
  """
  @spec allowed?(:inet.ip_address(), [{tuple(), non_neg_integer()}]) :: boolean()
  def allowed?(address, allow) when is_list(allow) do
    # IPv4 carried inside IPv6 (::ffff:a.b.c.d, 64:ff9b::a.b.c.d) is judged as that IPv4 address,
    # so the never-allowed and allowlist checks see what the socket actually reaches (api).
    address = embedded_v4(address)

    cond do
      Enum.any?(@never_allowed, &in_cidr?(address, &1)) -> false
      Enum.any?(allow, &in_cidr?(address, &1)) -> true
      true -> not denied?(address)
    end
  end

  @doc """
  Parses and validates an allowlist of CIDR strings. Raises on a malformed entry, a range wider
  than /8 (IPv4) or /32 (IPv6), or one that overlaps link-local or metadata space.
  """
  @spec parse_allow!([binary()]) :: [{tuple(), non_neg_integer()}]
  def parse_allow!(cidrs) when is_list(cidrs), do: Enum.map(cidrs, &parse_allowed_cidr!/1)

  @doc "Validates the configured allowlist (called at boot, so a bad entry stops the node)."
  @spec validate_config!() :: :ok
  def validate_config! do
    configured_allow() |> parse_allow!() |> then(&:persistent_term.put({__MODULE__, :allow}, &1))
    :ok
  end

  defp parse_allowed_cidr!(cidr) do
    {network, bits} = parse_cidr!(cidr)
    min = Map.fetch!(@min_prefix, tuple_size(network))

    if bits < min,
      do: raise(ArgumentError, "provider outbound allow #{cidr}: wider than /#{min}")

    if Enum.any?(@never_allowed, &overlaps?({network, bits}, &1)),
      do: raise(ArgumentError, "provider outbound allow #{cidr}: link-local or metadata space")

    # ::1/128 is IPv6 loopback, not a carried IPv4 address (dev allows it for the simulator).
    if {network, bits} != {{0, 0, 0, 0, 0, 0, 0, 1}, 128} and
         Enum.any?(@v4_embedding, &overlaps?({network, bits}, &1)),
       do:
         raise(
           ArgumentError,
           "provider outbound allow #{cidr}: an IPv6 range that carries IPv4; name the IPv4 range"
         )

    {network, bits}
  end

  defp overlaps?({network, bits}, {other, other_bits})
       when tuple_size(network) == tuple_size(other) do
    shortest = min(bits, other_bits)
    in_cidr?(network, {other, shortest}) or in_cidr?(other, {network, shortest})
  end

  defp overlaps?(_range, _other), do: false

  defp all_allowed(addresses, host, allow) do
    if Enum.all?(addresses, &allowed?(&1, allow)),
      do: :ok,
      else: {:error, {:outbound_address_denied, host}}
  end

  # A resolver only maps names to addresses; whatever it answers is still checked. The test
  # environment configures one for its fake provider hosts (`:provider_outbound, :resolver`).
  defp resolve(host, guard_opts) do
    resolver = Keyword.get(guard_opts, :resolver) || configured_resolver() || (&resolve_dns/1)

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

  # Tests pass CIDR strings; the node uses the list validated at boot.
  defp allow(guard_opts) do
    case Keyword.fetch(guard_opts, :allow) do
      {:ok, cidrs} ->
        parse_allow!(cidrs)

      :error ->
        :persistent_term.get({__MODULE__, :allow}, nil) || parse_allow!(configured_allow())
    end
  end

  defp configured_resolver do
    case :cadence |> Application.get_env(:provider_outbound, []) |> Keyword.get(:resolver) do
      {module, function} -> &apply(module, function, [&1])
      nil -> nil
    end
  end

  defp configured_allow,
    do: :cadence |> Application.get_env(:provider_outbound, []) |> Keyword.get(:allow, [])

  # An IPv4-mapped (::ffff:a.b.c.d) or well-known NAT64 (64:ff9b::a.b.c.d) address is the IPv4
  # address inside it.
  defp embedded_v4({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: v4_of(high, low)
  defp embedded_v4({0x0064, 0xFF9B, 0, 0, 0, 0, high, low}), do: v4_of(high, low)
  defp embedded_v4(address), do: address

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

  defp parse_cidr!(cidr) when is_binary(cidr) do
    {address, bits} =
      case String.split(String.trim(cidr), "/") do
        [address, bits] -> {address, bits}
        [address] -> {address, nil}
        _other -> raise ArgumentError, "provider outbound allow #{inspect(cidr)}: malformed"
      end

    case :inet.parse_strict_address(String.to_charlist(address)) do
      {:ok, parsed} ->
        max = if tuple_size(parsed) == 4, do: 32, else: 128
        {parsed, prefix!(bits, max, cidr)}

      {:error, _reason} ->
        raise ArgumentError, "provider outbound allow #{inspect(cidr)}: malformed"
    end
  end

  defp parse_cidr!(cidr),
    do: raise(ArgumentError, "provider outbound allow #{inspect(cidr)}: malformed")

  defp prefix!(nil, max, _cidr), do: max

  defp prefix!(bits, max, cidr) do
    case Integer.parse(bits) do
      {value, ""} when value >= 0 and value <= max -> value
      _other -> raise ArgumentError, "provider outbound allow #{inspect(cidr)}: malformed prefix"
    end
  end

  defp address_host({_, _, _, _} = v4), do: v4 |> :inet.ntoa() |> to_string()
  # URI.to_string/1 brackets an IPv6 host itself.
  defp address_host(v6), do: v6 |> :inet.ntoa() |> to_string()
end
