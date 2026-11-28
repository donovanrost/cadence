defmodule Cadence.ProviderAdapters.InboundSocket.Authorization do
  @moduledoc """
  A listener owner's in-memory authorization for one transport. The acceptor uses the entries
  supplied by its registrations. Both certificate checks use the same index, with no database
  access from a handshake.
  """

  alias Cadence.Comms.ProviderDeliveryListenerRead
  alias Cadence.Platform.ScopedReadUpdates

  @events [:provider_delivery_credentials_changed, :configuration_changed, :providers_changed]
  @refresh_ms 30_000
  @max_age_ms 2 * @refresh_ms

  defstruct [
    :table,
    :mode,
    :organization_id,
    :mission_id,
    :provider_id,
    :binding_id,
    :ref,
    :host,
    :port
  ]

  def start(mode, org, mission, metadata, config) do
    provider = metadata["mission_provider_id"]
    binding = metadata["materialized_from_transport_id"]

    if is_binary(org) and is_binary(provider) and is_binary(binding) and
         metadata["transport_origin"] == "provider_managed" do
      start_watch(mode, org, mission, provider, binding, config)
    else
      if mode == :plaintext, do: {:ok, nil}, else: {:error, :wrong_binding}
    end
  end

  defp start_watch(mode, org, mission, provider, binding, config) do
    policy = %__MODULE__{
      table: :ets.new(__MODULE__, [:protected, read_concurrency: true]),
      mode: mode,
      organization_id: org,
      mission_id: mission,
      provider_id: provider,
      binding_id: binding,
      ref: config.delivery_credential_ref,
      host: config.host,
      port: config.port
    }

    Enum.each(@events, &ScopedReadUpdates.subscribe(&1, org, mission))
    refresh(policy)

    with :ok <- listener_ready(policy) do
      schedule_refresh()
      {:ok, policy}
    end
  end

  def schedule_refresh,
    do: Process.send_after(self(), :refresh_delivery_authorization, @refresh_ms)

  def invalidation?(
        %__MODULE__{organization_id: org, mission_id: mission},
        {event, org, mission}
      ),
      do: event in @events

  def invalidation?(_policy, _message), do: false

  def refresh(nil), do: :ok

  def refresh(%__MODULE__{} = policy) do
    # Invalidate before a reload so a failed query or concurrent handshake cannot retain access
    # after notification of a revocation. A successful reload replaces the snapshot atomically.
    :ets.delete(policy.table, :snapshot)
    at = System.monotonic_time(:millisecond)
    result = load(policy)
    :ets.insert(policy.table, {:snapshot, at, result})
    :ok
  rescue
    _error -> :ok
  end

  defp load(policy) do
    case ProviderDeliveryListenerRead.transport(
           policy.organization_id,
           policy.mission_id,
           policy.binding_id
         ) do
      {:ok, transport} -> load_transport(policy, transport)
      {:error, _reason} -> {:error, :wrong_binding}
    end
  end

  defp load_transport(%__MODULE__{mode: :plaintext}, %{
         configuration: %{"delivery_auth" => "mtls"}
       }),
       do: {:error, :mode_mismatch}

  defp load_transport(%__MODULE__{mode: :plaintext}, _transport), do: {:ok, %{}}

  defp load_transport(%__MODULE__{mode: :mtls}, %{configuration: config})
       when not is_map_key(config, "delivery_auth"),
       do: {:error, :mode_mismatch}

  defp load_transport(%__MODULE__{mode: :mtls}, %{configuration: %{"delivery_auth" => mode}})
       when mode != "mtls",
       do: {:error, :mode_mismatch}

  defp load_transport(policy, transport) do
    config = transport.configuration

    with true <- transport.origin == "provider_managed",
         true <- transport.mission_provider_id == policy.provider_id,
         true <- config["delivery_auth"] == "mtls",
         true <- config["delivery_credential_ref"] == policy.ref,
         true <- config["host"] == policy.host and config["port"] == policy.port,
         {:ok, generations} <-
           ProviderDeliveryListenerRead.generations(
             policy.organization_id,
             policy.mission_id,
             policy.provider_id,
             policy.binding_id,
             policy.ref
           ) do
      {:ok, Map.new(generations, &{&1.fingerprint, &1})}
    else
      _not_eligible -> {:error, :wrong_binding}
    end
  end

  def listener_ready(nil), do: :ok

  def listener_ready(%__MODULE__{} = policy) do
    with {:ok, _leaves} <- snapshot(policy), do: :ok
  end

  def authorize(%__MODULE__{mode: :mtls} = policy, fingerprint) do
    with {:ok, leaves} <- snapshot(policy),
         {:ok, leaf} <- fetch_leaf(leaves, fingerprint),
         :ok <- check_generation(leaf) do
      {:ok,
       %{
         "provider_binding_id" => policy.binding_id,
         "client_certificate_fingerprint" => fingerprint,
         "client_certificate_generation" => leaf.generation
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize(_policy, _fingerprint), do: {:error, :wrong_binding}

  def stream_allowed?(nil, nil), do: :ok

  def stream_allowed?(%__MODULE__{mode: :plaintext} = policy, nil), do: listener_ready(policy)

  def stream_allowed?(policy, %{"client_certificate_fingerprint" => fingerprint} = identity) do
    case authorize(policy, fingerprint) do
      {:ok, ^identity} -> :ok
      {:ok, _other} -> {:error, :wrong_binding}
      {:error, _reason} = error -> error
    end
  end

  def stream_allowed?(_policy, _identity), do: {:error, :mode_mismatch}

  defp check_generation(%{state: "revoked"}), do: {:error, :revoked}

  defp check_generation(leaf) do
    if ProviderDeliveryListenerRead.live_generation?(leaf, DateTime.utc_now()),
      do: :ok,
      else: {:error, :expired}
  end

  defp fetch_leaf(leaves, fingerprint) do
    case Map.fetch(leaves, fingerprint) do
      {:ok, _leaf} = result -> result
      :error -> {:error, :unknown_leaf}
    end
  end

  defp snapshot(policy) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(policy.table, :snapshot) do
      [{:snapshot, at, result}] when now - at < @max_age_ms -> result
      _stale -> {:error, :stale_index}
    end
  rescue
    ArgumentError -> {:error, :stale_index}
  end
end
