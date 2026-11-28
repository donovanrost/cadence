defmodule Cadence.Comms.ListenClaims do
  @moduledoc """
  SAFETY (multi-tenant isolation, director/lead 11-16): a listen-mode host:port belongs to ONE
  mission. A provider's TCP connection says nothing about which mission it serves; a listener
  routes an accepted peer among its own mission's contacts only (by the first frame's SCID, or
  as its single peer). If two missions listened on one host:port, one mission's pass could be
  taken by the other's listener and its telemetry stored as the other mission's spacecraft.

  Claims span every organization and come from the latest active transport or provider profile
  versions. A shared claim carries the stable transport ID, or the profile ID for a standalone
  profile. Plaintext Shared admits one binding. Distinct bindings can share an endpoint with
  mTLS and a common bind address and ownership mode.

  - at save: `guard/3` around a provider-profile or transport write, under a per-port advisory
    lock so two missions saving at once can't both pass;
  - at contact start: `check_paths/2` over each path's pinned provider bindings.

  The refusal is `{:listen_endpoint_claimed, %{host, port}}` and never names the other mission:
  it may be another organization's.
  """

  import Ecto.Query

  alias Cadence.Comms.{ListenerChoice, TransportRow}
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @wildcard_hosts ["0.0.0.0", "::", "", "*"]
  @loopback_hosts ["localhost", "127.0.0.1"]

  @type endpoint :: %{host: binary(), port: pos_integer()}
  @type reason :: {atom(), endpoint()}

  @doc "The words a form shows for a refused endpoint (class-level; names no mission)."
  @spec message() :: binary()
  def message,
    do: "Another mission already listens on this host and port. Choose a different port."

  @doc """
  The listen endpoint a provider configuration binds, or nil: only `mode: listen` with a fixed
  port claims one (port 0 asks the OS for a free port).
  """
  @spec endpoint(term()) :: endpoint() | nil
  def endpoint(configuration) when is_map(configuration) do
    with mode when mode in ["listen", :listen] <- get(configuration, :mode),
         {:ok, port} <- port(get(configuration, :port)) do
      %{host: host(get(configuration, :host)), port: port}
    else
      _not_listening -> nil
    end
  end

  def endpoint(_configuration), do: nil

  @doc """
  `:ok` unless another mission claims an endpoint overlapping `endpoint` (nil: nothing to
  check).
  """
  @spec check(binary(), endpoint() | nil) :: :ok | {:error, reason()}
  def check(_mission_id, nil), do: :ok

  def check(mission_id, endpoint) when is_binary(mission_id),
    do: check_mission(mission_id, endpoint, claims(endpoint.port))

  @doc "Checks the proposed configuration against current claims, before the write's locked check."
  def check_configuration(mission_id, configuration, owner) do
    case claim(mission_id, configuration, owner) do
      nil -> :ok
      candidate -> check_candidate(candidate, claims(candidate.endpoint.port))
    end
  end

  @doc """
  Runs `write` (a fun returning `{:ok, _} | {:error, _}`) only if `configuration`'s listen
  endpoint, if any, isn't another mission's, holding the port's advisory lock until the write
  commits. An inactive write (a tombstone, an archive) claims nothing and isn't checked.
  """
  @spec guard(binary(), term(), (-> {:ok, term()} | {:error, term()}), term()) ::
          {:ok, term()} | {:error, term()}
  def guard(mission_id, configuration, write, owner \\ nil) when is_function(write, 0) do
    case claim(mission_id, configuration, owner) do
      nil ->
        write.()

      candidate ->
        Repo.transaction(fn -> locked_write(candidate, write) end)
    end
  end

  defp locked_write(%{endpoint: %{port: port}} = candidate, write) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["listen_port:#{port}"])

    with :ok <- check_candidate(candidate, claims(port)),
         {:ok, result} <- write.() do
      result
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Checks new claims together with the other staged transport claims on those ports."
  def check_staged(mission_id, proposed, request) do
    staged_by_owner =
      Map.new(proposed, fn {owner, config} -> {owner, claim(mission_id, config, owner)} end)

    staged_by_port =
      staged_by_owner
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(& &1.endpoint.port)

    persisted_by_port =
      staged_by_port |> Map.keys() |> claims_on_ports() |> Enum.group_by(& &1.endpoint.port)

    position = Map.new(request, fn {index, owner} -> {owner, index} end)

    Enum.find_value(request, :ok, fn {index, owner} ->
      with %{endpoint: %{port: port}} = candidate <- Map.get(staged_by_owner, owner),
           existing =
             staged_persisted(
               Map.get(persisted_by_port, port, []),
               staged_by_owner,
               mission_id,
               position,
               index
             ),
           staged = Enum.filter(staged_by_port[port], &(Map.get(position, &1.owner, -1) < index)),
           {:error, reason} <- check_shared_at_stage(candidate, existing ++ staged) do
        {:error, index, reason}
      else
        _accepted -> nil
      end
    end)
  end

  # Another operation can release a claim before this one. The write checks the same endpoint
  # against the actual rows under the lock, so applying in a different order fails safely.
  defp staged_persisted(claims, staged, mission_id, position, index) do
    Enum.reject(claims, fn claim ->
      claim.mission_id == mission_id and Map.has_key?(staged, claim.owner) and
        Map.get(position, claim.owner, -1) < index
    end)
  end

  defp check_shared_at_stage(candidate, claims) do
    overlapping = Enum.filter(claims, &collides?(&1, candidate))

    if candidate.shared? or Enum.any?(overlapping, &(&1.shared? and not &1.projected?)),
      do: check_overlapping(candidate, overlapping),
      else: :ok
  end

  defp check_candidate(candidate, claims) do
    check_overlapping(candidate, Enum.filter(claims, &collides?(&1, candidate)))
  end

  defp check_overlapping(candidate, overlapping) do
    with :ok <- exclusive_mission(candidate.mission_id, candidate.endpoint, overlapping),
         :ok <- shared_allowlist(candidate) do
      Enum.find_value(overlapping, :ok, &conflict_result(candidate, &1))
    end
  end

  defp conflict_result(candidate, other) do
    case conflict(candidate, other) do
      nil -> nil
      reason -> {:error, {reason, candidate.endpoint}}
    end
  end

  defp shared_allowlist(%{shared?: true, configuration: config, endpoint: endpoint}) do
    case ListenerChoice.check_allowlist(config) do
      :ok -> :ok
      {:error, reason} -> {:error, {reason, endpoint}}
    end
  end

  defp shared_allowlist(_claim), do: :ok

  defp conflict(_candidate, %{projected?: true}), do: nil

  defp conflict(%{owner: owner}, %{owner: owner}) when not is_nil(owner), do: nil

  defp conflict(a, b) when a.shared? or b.shared?, do: shared_conflict(a, b)
  defp conflict(a, b) when a.mode != b.mode, do: :listen_endpoint_mode_mismatch
  defp conflict(_a, _b), do: nil

  defp shared_conflict(a, b) when a.mode == :plaintext or b.mode == :plaintext,
    do: :shared_listener_requires_mtls

  defp shared_conflict(a, b) when a.shared? != b.shared?, do: :listen_endpoint_listener_mismatch
  defp shared_conflict(a, b) when a.bind != b.bind, do: :shared_listener_bind_mismatch
  defp shared_conflict(_a, _b), do: nil

  defp collides?(a, b) do
    if a.shared? or b.shared?,
      do: overlaps?(a.bind, b.bind),
      else: overlaps?(a.endpoint, b.endpoint)
  end

  defp claims(port), do: claims_on_ports([port])

  defp claims_on_ports([]), do: []
  defp claims_on_ports(ports), do: profile_claims(ports) ++ transport_claims(ports)

  defp check_mission(mission_id, endpoint, claims) do
    exclusive_mission(
      mission_id,
      endpoint,
      Enum.filter(claims, &overlaps?(&1.endpoint, endpoint))
    )
  end

  defp exclusive_mission(mission_id, endpoint, claims) do
    if Enum.any?(claims, &(&1.mission_id != mission_id)),
      do: {:error, {:listen_endpoint_claimed, endpoint}},
      else: :ok
  end

  defp check_path(_mission_id, nil, _mode), do: :ok

  defp check_path(mission_id, endpoint, mode) do
    overlaps = Enum.filter(claims(endpoint.port), &overlaps?(&1.endpoint, endpoint))

    with :ok <- exclusive_mission(mission_id, endpoint, overlaps) do
      if Enum.any?(overlaps, &(not &1.projected? and &1.mode != mode)),
        do: {:error, {:listen_endpoint_mode_mismatch, endpoint}},
        else: :ok
    end
  end

  @doc """
  `check/2` for every listen binding on a contact's paths (fail closed at start). A refusal also
  names the binding (`provider_binding_id`) and its transport (`transport_id` and
  `transport_name`, from the binding's metadata; nil when unknown), so the start failure can say
  which transport's port to change.
  """
  @spec check_paths(binary(), [map()]) :: :ok | {:error, reason()}
  def check_paths(mission_id, paths) when is_binary(mission_id) and is_list(paths) do
    paths
    |> Enum.flat_map(&(Map.get(&1, :provider_bindings) || []))
    |> Enum.reduce_while(:ok, fn binding, :ok ->
      config = Map.get(binding, :configuration) || %{}

      case check_path(mission_id, endpoint(config), auth_mode(config)) do
        :ok ->
          {:cont, :ok}

        {:error, {reason, endpoint}} ->
          {:halt, {:error, {reason, Map.merge(endpoint, binding_ref(binding))}}}
      end
    end)
  end

  defp binding_ref(binding) do
    metadata = Map.get(binding, :metadata) || %{}

    %{
      provider_binding_id: Map.get(binding, :provider_binding_id),
      transport_id: metadata["materialized_from_transport_id"],
      transport_name: metadata["display_name"]
    }
  end

  defp profile_claims(ports),
    do: ports |> ProfileStore.latest_provider_profiles_on_ports() |> claimed_endpoints(:profile)

  # Transports mentioning `port`, at their LATEST version: only one that is
  # still active and still listens there claims it.
  defp transport_claims(ports) do
    port_text = Enum.map(ports, &Integer.to_string/1)

    candidates =
      from(row in TransportRow,
        where: fragment("?->'value'->>'port'", row.configuration) in ^port_text,
        select: %{mission_id: row.mission_id, transport_id: row.transport_id},
        distinct: true
      )

    from(row in TransportRow,
      join: candidate in subquery(candidates),
      on: candidate.mission_id == row.mission_id and candidate.transport_id == row.transport_id,
      distinct: [row.mission_id, row.transport_id],
      order_by: [row.mission_id, row.transport_id, desc: row.version],
      select: %{
        mission_id: row.mission_id,
        owner_id: row.transport_id,
        lifecycle_state: row.lifecycle_state,
        configuration: row.configuration
      }
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | configuration: JsonDocument.unwrap_value(&1.configuration)})
    |> claimed_endpoints(:transport)
  end

  defp claimed_endpoints(latest_rows, kind) do
    for %{lifecycle_state: state, configuration: configuration} = row <- latest_rows,
        state in ["active", :active],
        entry = claim(row.mission_id, configuration, claim_owner(row, kind)),
        do: %{entry | projected?: is_binary(Map.get(row, :materialized_transport))}
  end

  defp claim_owner(%{materialized_transport: id}, _kind) when is_binary(id), do: {:transport, id}
  defp claim_owner(row, kind), do: {kind, row.owner_id}

  defp claim(mission_id, configuration, owner) do
    if endpoint = endpoint(configuration) do
      %{
        mission_id: mission_id,
        owner: owner,
        projected?: false,
        endpoint: endpoint,
        bind: %{endpoint | host: bind_host(get(configuration, :host))},
        mode: auth_mode(configuration),
        shared?: ListenerChoice.shared?(configuration),
        configuration: configuration
      }
    end
  end

  # InboundSocket binds an unspecified address when the host isn't a literal IP.
  defp bind_host(nil), do: "127.0.0.1"

  defp bind_host(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> ip |> :inet.ntoa() |> List.to_string()
      {:error, _reason} -> "0.0.0.0"
    end
  end

  defp bind_host(_host), do: "0.0.0.0"

  defp auth_mode(configuration) do
    if get(configuration, :delivery_auth) in ["mtls", :mtls], do: :mtls, else: :plaintext
  end

  # Two binds collide on the same port when either is a wildcard or both name the same host.
  @doc """
  Whether two listen endpoints collide on the node: the same port, and the same host or either
  a wildcard. The claim check's own comparison; planning's listener overlap uses it too (#361).
  """
  @spec overlaps?(endpoint(), endpoint()) :: boolean()
  def overlaps?(%{port: port, host: a}, %{port: port, host: b}),
    do: a == b or a in @wildcard_hosts or b in @wildcard_hosts

  def overlaps?(_claim, _endpoint), do: false

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp port(port) when is_integer(port) and port > 0 and port <= 65_535, do: {:ok, port}

  defp port(port) when is_binary(port) do
    case Integer.parse(String.trim(port)) do
      {value, ""} -> port(value)
      _other -> :error
    end
  end

  defp port(_port), do: :error

  defp host(host) when is_binary(host) do
    case String.downcase(String.trim(host)) do
      loopback when loopback in @loopback_hosts -> "127.0.0.1"
      other -> other
    end
  end

  defp host(nil), do: "127.0.0.1"
  defp host(host), do: to_string(host)
end
