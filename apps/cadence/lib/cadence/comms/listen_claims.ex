defmodule Cadence.Comms.ListenClaims do
  @moduledoc """
  SAFETY (multi-tenant isolation, director/lead 11-16): a listen-mode host:port belongs to ONE
  mission. A provider's TCP connection says nothing about which mission it serves; a listener
  routes an accepted peer among its own mission's contacts only (by the first frame's SCID, or
  as its single peer). If two missions listened on one host:port, one mission's pass could be
  taken by the other's listener and its telemetry stored as the other mission's spacecraft.

  A mission's claim on a listen endpoint is any of its latest ACTIVE provider profiles or
  transports whose configuration listens there. Claims span every organization, because the port
  is a resource of the node, not of a tenant. The same mission may reuse an endpoint (a station
  pair sharing one port by design); only another mission's use is refused:

  - at save: `guard/3` around a provider-profile or transport write, under a per-port advisory
    lock so two missions saving at once can't both pass;
  - at contact start: `check_paths/2` over each path's pinned provider bindings.

  The refusal is `{:listen_endpoint_claimed, %{host, port}}` and never names the other mission:
  it may be another organization's.
  """

  import Ecto.Query

  alias Cadence.Comms.TransportRow
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @wildcard_hosts ["0.0.0.0", "::", "", "*"]
  @loopback_hosts ["localhost", "127.0.0.1"]

  @type endpoint :: %{host: binary(), port: pos_integer()}
  @type reason :: {:listen_endpoint_claimed | :listen_endpoint_mode_mismatch, map()}

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
    do: check_claims(mission_id, endpoint, nil, nil)

  @doc """
  Runs `write` (a fun returning `{:ok, _} | {:error, _}`) only if `configuration`'s listen
  endpoint, if any, isn't another mission's, holding the port's advisory lock until the write
  commits. An inactive write (a tombstone, an archive) claims nothing and isn't checked.
  """
  @spec guard(binary(), term(), (-> {:ok, term()} | {:error, term()}), term()) ::
          {:ok, term()} | {:error, term()}
  def guard(mission_id, configuration, write, owner \\ nil) when is_function(write, 0) do
    case endpoint(configuration) do
      nil ->
        write.()

      endpoint ->
        mode = auth_mode(configuration)
        Repo.transaction(fn -> locked_write(mission_id, endpoint, mode, owner, write) end)
    end
  end

  defp locked_write(mission_id, %{port: port} = endpoint, mode, owner, write) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["listen_port:#{port}"])

    with :ok <- check_claims(mission_id, endpoint, mode, owner),
         {:ok, result} <- write.() do
      result
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp check_claims(_mission_id, nil, _mode, _owner), do: :ok

  defp check_claims(mission_id, %{port: port} = endpoint, mode, owner) do
    claims = overlapping_claims(port, endpoint)

    cond do
      Enum.any?(claims, &(&1.mission_id != mission_id)) ->
        {:error, {:listen_endpoint_claimed, endpoint}}

      mode && Enum.any?(claims, &conflicting_mode?(&1, owner, mode)) ->
        {:error, {:listen_endpoint_mode_mismatch, endpoint}}

      true ->
        :ok
    end
  end

  defp overlapping_claims(port, endpoint) do
    (profile_claims(port) ++ transport_claims(port))
    |> Enum.filter(&overlaps?(&1.endpoint, endpoint))
  end

  defp conflicting_mode?(%{projected?: true}, _owner, _mode), do: false
  defp conflicting_mode?(%{owner: owner}, owner, _mode), do: false
  defp conflicting_mode?(claim, _owner, mode), do: claim.mode != mode

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

      case check_claims(mission_id, endpoint(config), auth_mode(config), nil) do
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

  defp profile_claims(port),
    do: port |> ProfileStore.latest_provider_profiles_on_port() |> claimed_endpoints(:profile)

  # Transports mentioning `port`, at their LATEST version: only one that is
  # still active and still listens there claims it.
  defp transport_claims(port) do
    port_text = Integer.to_string(port)

    candidates =
      from(row in TransportRow,
        where: fragment("(?->'value'->>'port') = ?", row.configuration, ^port_text),
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
        endpoint = endpoint(configuration),
        not is_nil(endpoint),
        do: %{
          mission_id: row.mission_id,
          owner: {kind, row.owner_id},
          projected?: is_binary(Map.get(row, :materialized_transport)),
          endpoint: endpoint,
          mode: auth_mode(configuration)
        }
  end

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
