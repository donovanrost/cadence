defmodule Cadence.Comms.TransportStore do
  @moduledoc """
  Persistence boundary for mission-owned Transports.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.{
    ListenClaims,
    PeerAddresses,
    ProviderDeliveryListenerRead,
    ProviderTransportBasis,
    Transport,
    TransportKind,
    TransportRow
  }

  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Listing
  alias Cadence.Missions
  alias Cadence.Persistence.BulkLookup
  alias Cadence.Platform.RedactedJson
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo
  alias Cadence.Secrets.ProviderDeliveryListenerIdentity, as: ServerIdentity

  @max_batch_size 100

  @spec persist_transport(binary(), Transport.t(), keyword()) ::
          {:ok, Transport.t()} | {:error, term()}
  def persist_transport(organization_id, %Transport{} = transport, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    with :ok <- allow_delivery_auth(transport),
         {:ok, scoped_transport} <- put_organization_scope(transport, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_transport.organization_id, scoped_transport.mission_id),
         {:ok, normalized_transport} <- normalize_transport(scoped_transport, opts) do
      # SAFETY: a listen host:port is one mission's (ListenClaims); fail closed at save.
      ListenClaims.guard(
        normalized_transport.mission_id,
        claimed_configuration(normalized_transport),
        fn -> store_version(normalized_transport, opts) end,
        {:transport, normalized_transport.transport_id}
      )
      |> publish_mtls_transport(normalized_transport)
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish_mtls_transport(result, %{configuration: %{"delivery_auth" => "mtls"}} = transport) do
    ScopedReadUpdates.publish_result(
      result,
      :configuration_changed,
      transport.organization_id,
      transport.mission_id
    )
  end

  defp publish_mtls_transport(result, _transport), do: result

  defp store_version(%Transport{version: 1} = transport, _opts), do: insert_transport(transport)

  defp store_version(transport, opts) do
    Repo.transact(fn ->
      lock_transport_version(transport.mission_id, transport.transport_id)

      with :ok <- authorize_delivery_transition(transport, opts) do
        insert_transport(transport)
      end
    end)
  end

  @doc "Fetches the latest active transport under its version-write lock in the caller's transaction."
  @spec lock_current_transport(binary(), binary(), binary()) ::
          {:ok, Transport.t()} | {:error, term()}
  def lock_current_transport(organization_id, mission_id, transport_id) do
    lock_transport_version(mission_id, transport_id)
    fetch_transport(organization_id, mission_id, transport_id)
  end

  defp lock_transport_version(mission_id, transport_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
      "transport_version:#{mission_id}:#{transport_id}"
    ])
  end

  # Only a provider-managed transport may bind a provider delivery credential.
  defp allow_delivery_auth(%Transport{
         origin: :direct,
         lifecycle_state: :active,
         configuration: config
       })
       when is_map(config) do
    case Map.get(config, "delivery_auth", Map.get(config, :delivery_auth)) do
      mode when mode in [nil, "plaintext", :plaintext] -> :ok
      mode when mode in ["mtls", :mtls] -> {:error, :delivery_binding_unavailable}
      _unknown -> {:error, :provider_delivery_auth_unsupported}
    end
  end

  defp allow_delivery_auth(_transport), do: :ok

  defp authorize_delivery_transition(%Transport{lifecycle_state: :archived}, _opts), do: :ok

  defp authorize_delivery_transition(next, opts) do
    case latest_versioned_row(next.organization_id, next.mission_id, next.transport_id) do
      %TransportRow{} = row ->
        current = TransportRow.to_domain(row)

        if current.configuration["delivery_auth"] == "mtls" do
          approve_plaintext_transition(
            current,
            next,
            Keyword.get(opts, :authorize_delivery_downgrade)
          )
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  defp approve_plaintext_transition(
         _current,
         %Transport{configuration: %{"delivery_auth" => "mtls"}},
         _authorize
       ),
       do: :ok

  defp approve_plaintext_transition(current, next, authorize) when is_function(authorize, 2) do
    peer_addresses = next.configuration["expected_peer_addresses"]

    if next.configuration["mode"] == "listen" and
         PeerAddresses.classify(peer_addresses) == :ok,
       do: authorize.(current, next),
       else: {:error, :delivery_auth_downgrade_required}
  end

  defp approve_plaintext_transition(_current, _next, _authorize),
    do: {:error, :delivery_auth_downgrade_required}

  defp insert_transport(normalized_transport) do
    with :ok <- validate_delivery_binding(normalized_transport),
         {:ok, transport_with_provider} <- materialize_provider_profile(normalized_transport),
         {:ok, _row} <-
           Repo.insert(TransportRow.changeset(transport_with_provider),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :transport_id, :version]
           ) do
      fetch_transport_version(
        transport_with_provider.organization_id,
        transport_with_provider.mission_id,
        transport_with_provider.transport_id,
        transport_with_provider.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_delivery_binding(
         %Transport{
           lifecycle_state: :active,
           configuration: %{"delivery_auth" => "mtls"} = config
         } = transport
       ) do
    ProviderDeliveryListenerRead.check_binding(
      transport.organization_id,
      transport.mission_id,
      transport.mission_provider_id,
      transport.transport_id,
      config["delivery_credential_ref"]
    )
  end

  defp validate_delivery_binding(_transport), do: :ok

  # Only an active transport claims its listen endpoint; an archived one releases it.
  defp claimed_configuration(%Transport{lifecycle_state: :active, configuration: config}),
    do: config

  defp claimed_configuration(%Transport{}), do: nil

  @spec fetch_transport(binary(), binary(), binary()) :: {:ok, Transport.t()} | {:error, term()}
  def fetch_transport(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    case latest_versioned_row(organization_id, mission_id, transport_id) do
      nil ->
        {:error, :transport_not_found}

      %TransportRow{lifecycle_state: "archived"} ->
        {:error, :transport_not_found}

      %TransportRow{} = row ->
        {:ok, TransportRow.to_domain(row)}
    end
  end

  @doc "Fetches the active latest versions for one bounded transport batch in one query."
  @spec fetch_transports(binary(), binary(), [binary()]) ::
          {:ok, %{optional(binary()) => Transport.t()}} | {:error, :batch_bounds_exceeded}
  def fetch_transports(organization_id, mission_id, transport_ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(transport_ids) do
    case bounded_transport_ids(transport_ids) do
      {:error, reason} ->
        {:error, reason}

      {:ok, []} ->
        {:ok, %{}}

      {:ok, ids} ->
        latest =
          TransportRow
          |> where(
            [row],
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.transport_id in ^ids
          )
          |> distinct([row], row.transport_id)
          |> order_by([row], asc: row.transport_id, desc: row.version)
          |> subquery()
          |> where([row], row.lifecycle_state != "archived")
          |> Repo.all()

        {:ok, Map.new(latest, fn row -> {row.transport_id, TransportRow.to_domain(row)} end)}
    end
  end

  defp bounded_transport_ids(transport_ids) do
    ids = Enum.take(transport_ids, @max_batch_size + 1)

    cond do
      length(ids) > @max_batch_size ->
        {:error, :batch_bounds_exceeded}

      not Enum.all?(ids, &(is_binary(&1) and &1 != "")) ->
        {:error, :batch_bounds_exceeded}

      true ->
        {:ok, Enum.uniq(ids)}
    end
  end

  @spec fetch_transport_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, Transport.t()} | {:error, term()}
  def fetch_transport_version(organization_id, mission_id, transport_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_integer(version) and version > 0 do
    case Repo.get_by(TransportRow,
           organization_id: organization_id,
           mission_id: mission_id,
           transport_id: transport_id,
           version: version
         ) do
      nil -> {:error, :transport_not_found}
      %TransportRow{} = row -> {:ok, TransportRow.to_domain(row)}
    end
  end

  @doc "Exact mission transport versions keyed by `{id, version}`."
  def fetch_transport_versions(organization_id, mission_id, keys) do
    TransportRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> BulkLookup.by_version(:transport_id, keys)
    |> Map.new(&{{&1.transport_id, &1.version}, TransportRow.to_domain(&1)})
  end

  @doc false
  def route_transports(organization_id, mission_id, station_ids, transport_ids) do
    latest =
      from(row in TransportRow,
        where: row.organization_id == ^organization_id and row.mission_id == ^mission_id,
        distinct: row.transport_id,
        order_by: [desc: row.version]
      )

    active = from(row in subquery(latest), where: row.lifecycle_state == "active")

    at_stations = BulkLookup.by_id(active, :ground_station_id, station_ids)
    loaded = MapSet.new(at_stations, & &1.transport_id)
    missing = Enum.reject(transport_ids, &MapSet.member?(loaded, &1))
    named = BulkLookup.by_id(active, :transport_id, missing)

    (at_stations ++ named)
    |> Enum.uniq_by(& &1.transport_id)
    |> Enum.map(&TransportRow.to_domain/1)
  end

  @doc "A mission's transports (latest versions); archived ones only with `include_archived: true` (U82)."
  @spec list_transports(binary(), binary(), keyword()) :: [Transport.t()]
  def list_transports(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    archived? = Keyword.get(opts, :include_archived, false)

    TransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.transport_id, desc: row.version)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.transport_id, row) end)
    |> Map.values()
    |> Enum.reject(&(&1.lifecycle_state == "archived" and not archived?))
    |> Enum.sort_by(& &1.display_name)
    |> Enum.map(&TransportRow.to_domain/1)
  end

  @doc "The latest version of each of `transport_ids` that isn't archived (the change-set kind's load)."
  @spec latest_transports(binary(), binary(), [binary()]) :: [Transport.t()]
  def latest_transports(organization_id, mission_id, transport_ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(transport_ids) do
    from(row in TransportRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.transport_id in ^transport_ids,
      distinct: row.transport_id,
      order_by: [asc: row.transport_id, desc: row.version]
    )
    |> Repo.all()
    |> Enum.reject(&(&1.lifecycle_state == "archived"))
    |> Enum.map(&TransportRow.to_domain/1)
  end

  @doc "Returns one bounded page of the active latest transport versions."
  @spec list_transports_page(binary(), binary(), keyword()) :: Listing.Page.t()
  def list_transports_page(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    %{page: page, page_size: page_size, offset: offset} = Listing.page_opts(opts)
    direction = if Keyword.get(opts, :direction) == :desc, do: :desc, else: :asc

    latest =
      TransportRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )
      |> distinct([row], row.transport_id)
      |> order_by([row], asc: row.transport_id, desc: row.version)

    filtered =
      latest
      |> subquery()
      |> where([row], row.lifecycle_state != "archived")
      |> apply_transport_search(Keyword.get(opts, :search))

    items =
      filtered
      |> order_by(^[{direction, :display_name}, {:asc, :transport_id}])
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&TransportRow.to_domain/1)

    %Listing.Page{
      items: items,
      total_count: Repo.aggregate(filtered, :count),
      page: page,
      page_size: page_size
    }
  end

  @spec list_transport_versions(binary(), binary(), binary()) :: [Transport.t()]
  def list_transport_versions(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    TransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_id == ^transport_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&TransportRow.to_domain/1)
  end

  @spec version_transport(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, Transport.t()} | {:error, term()}
  def version_transport(organization_id, mission_id, transport_id, attrs, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_map(attrs) and is_list(opts) do
    with {:ok, %Transport{} = current_transport} <-
           fetch_transport(organization_id, mission_id, transport_id),
         {:ok, %Transport{} = next_transport} <-
           build_next_transport_version(current_transport, attrs) do
      persist_transport(organization_id, next_transport, opts)
    end
  end

  @spec archive_transport(binary(), binary(), binary(), map()) ::
          {:ok, Transport.t()} | {:error, term()}
  def archive_transport(organization_id, mission_id, transport_id, metadata_patch \\ %{})
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_map(metadata_patch) do
    with {:ok, %Transport{} = current_transport} <-
           fetch_transport(organization_id, mission_id, transport_id) do
      archived =
        %Transport{
          current_transport
          | version: current_transport.version + 1,
            lifecycle_state: :archived,
            metadata:
              current_transport.metadata
              |> Map.merge(metadata_patch)
              |> Map.put("archived_at", DateTime.utc_now())
        }

      # Archiving releases what the transport holds (lead 11-16): its materialized provider
      # profile goes with it, in the same transaction, so its listen host:port is free again and no
      # pass can start through it.
      Repo.transaction(fn ->
        archive_with_profile(organization_id, current_transport, archived)
      end)
    end
  end

  defp archive_with_profile(organization_id, current, archived) do
    with {:ok, transport} <- persist_transport(organization_id, archived),
         :ok <- retire_materialized_profile(current) do
      transport
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp retire_materialized_profile(%Transport{materialized_provider_profile_id: id} = transport)
       when is_binary(id) and id != "" do
    case ProfileStore.fetch_provider_profile(transport.organization_id, transport.mission_id, id) do
      {:ok, profile} ->
        if profile.metadata["materialized_from_transport_id"] == transport.transport_id,
          do:
            deleted(
              ProfileStore.delete_provider_profile(
                transport.organization_id,
                transport.mission_id,
                id
              )
            ),
          else: :ok

      {:error, _gone} ->
        :ok
    end
  end

  defp retire_materialized_profile(_transport), do: :ok

  defp deleted({:ok, _profile}), do: :ok
  defp deleted({:error, reason}), do: {:error, reason}

  defp normalize_transport(%Transport{lifecycle_state: :archived} = transport, _opts),
    do: {:ok, transport}

  defp normalize_transport(%Transport{origin: :direct} = transport, _opts) do
    with {:ok, entry} <- TransportKind.fetch(transport.transport_kind),
         {:ok, configuration} <- entry.module.normalize_config(transport.configuration) do
      {:ok,
       %Transport{
         transport
         | configuration: configuration,
           adapter_key: entry.adapter_key,
           direction_capability:
             configuration
             |> Map.fetch!("direction_capability")
             |> direction_capability(),
           mission_provider_id: nil,
           mission_provider_version: nil,
           service_profile_ref: nil,
           delivery_profile_ref: nil,
           provider_configuration_snapshot: %{}
       }}
    end
  end

  defp normalize_transport(%Transport{origin: :provider_managed} = transport, opts) do
    with {:ok, %ProviderTransportBasis{} = provider} <- provider_transport_basis(opts) do
      derive_provider_transport(transport, provider)
    end
  end

  @doc """
  A provider-managed transport as it would be stored, without storing it: the provider's
  version, readiness and profiles checked, the configuration and direction derived from the
  delivery profile, exact profile refs and the provider snapshot filled in. The change-set kind's
  preview and an options read use it, so what they show is what an apply stores.
  """
  @spec derive_provider_transport(Transport.t(), ProviderTransportBasis.t()) ::
          {:ok, Transport.t()} | {:error, term()}
  def derive_provider_transport(
        %Transport{origin: :provider_managed} = transport,
        %ProviderTransportBasis{} = provider
      ) do
    with {:ok, provider_id, provider_version} <- provider_reference(transport),
         :ok <- require_provider_scope(transport, provider, provider_id),
         true <- provider.provider_version == provider_version,
         :ok <- require_validated_provider(provider),
         {:ok, service_profile} <-
           find_profile(provider, "service_profiles", transport.service_profile_ref),
         {:ok, delivery_profile} <-
           find_profile(provider, "delivery_profiles", transport.delivery_profile_ref),
         :ok <- require_profile_compatibility(service_profile, delivery_profile),
         :ok <- require_delivery_auth(provider, delivery_profile),
         {:ok, configuration} <- delivery_configuration(delivery_profile) do
      {:ok,
       %Transport{
         transport
         | transport_kind: :tcp_socket,
           adapter_key: :tcp_socket,
           direction_capability: provider_direction_capability(delivery_profile),
           configuration: configuration,
           mission_provider_id: provider.provider_id,
           mission_provider_version: provider.provider_version,
           service_profile_ref: exact_profile_ref(service_profile),
           delivery_profile_ref: exact_profile_ref(delivery_profile),
           provider_configuration_snapshot:
             provider_snapshot(provider, service_profile, delivery_profile, configuration)
       }}
    else
      false -> {:error, :mission_provider_version_not_current}
      {:error, reason} -> {:error, reason}
    end
  end

  defp materialize_provider_profile(%Transport{materialized_provider_profile_id: id} = transport)
       when is_binary(id) and id != "" do
    {:ok, transport}
  end

  defp materialize_provider_profile(%Transport{} = transport) do
    with {:ok, entry} <- TransportKind.fetch(transport.transport_kind),
         {:ok, provider_profile} <- entry.module.materialize_provider_profile(transport),
         {:ok, provider_profile} <-
           ProfileStore.persist_provider_profile(transport.organization_id, provider_profile,
             projecting_transport: transport.transport_id
           ) do
      {:ok,
       %Transport{
         transport
         | materialized_provider_profile_id: provider_profile.provider_profile_id
       }}
    end
  end

  defp latest_versioned_row(organization_id, mission_id, transport_id) do
    TransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_id == ^transport_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp apply_transport_search(query, nil), do: query
  defp apply_transport_search(query, ""), do: query

  defp apply_transport_search(query, search) when is_binary(search) do
    pattern = "%" <> Listing.escape_like(search) <> "%"

    where(
      query,
      [row],
      ilike(row.display_name, ^pattern) or ilike(row.transport_id, ^pattern)
    )
  end

  defp build_next_transport_version(%Transport{} = transport, attrs) when is_map(attrs) do
    {:ok,
     %Transport{
       transport
       | version: transport.version + 1,
         lifecycle_state: :active,
         display_name: Map.get(attrs, :display_name, transport.display_name),
         origin: Map.get(attrs, :origin, transport.origin),
         transport_kind: Map.get(attrs, :transport_kind, transport.transport_kind),
         direction_capability:
           Map.get(attrs, :direction_capability, transport.direction_capability),
         adapter_key: Map.get(attrs, :adapter_key, transport.adapter_key),
         configuration: Map.get(attrs, :configuration, transport.configuration),
         ground_station_id: Map.get(attrs, :ground_station_id, transport.ground_station_id),
         mission_provider_id: Map.get(attrs, :mission_provider_id, transport.mission_provider_id),
         mission_provider_version:
           Map.get(attrs, :mission_provider_version, transport.mission_provider_version),
         service_profile_ref: Map.get(attrs, :service_profile_ref, transport.service_profile_ref),
         delivery_profile_ref:
           Map.get(attrs, :delivery_profile_ref, transport.delivery_profile_ref),
         provider_configuration_snapshot: %{},
         materialized_provider_profile_id: nil,
         metadata: Map.merge(transport.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  defp provider_reference(%Transport{
         mission_provider_id: provider_id,
         mission_provider_version: provider_version
       })
       when is_binary(provider_id) and provider_id != "" and is_integer(provider_version) and
              provider_version > 0,
       do: {:ok, provider_id, provider_version}

  defp provider_reference(_transport), do: {:error, :mission_provider_reference_required}

  defp require_delivery_auth(%ProviderTransportBasis{delivery_auth: :mtls}, %{
         "delivery_auth" => "mtls",
         "direction" => "downlink",
         "egress" => %{"delivery_credential_ref" => "delivery_credential_" <> id}
       })
       when byte_size(id) in 1..255 do
    if ServerIdentity.configured?(), do: :ok, else: {:error, :delivery_tls_identity_unavailable}
  end

  defp require_delivery_auth(_provider, profile) do
    case profile["delivery_auth"] do
      auth when auth in [nil, "plaintext"] -> :ok
      _other -> {:error, :provider_delivery_auth_unsupported}
    end
  end

  defp delivery_configuration(delivery_profile) do
    case TCPSocket.from_delivery_profile(delivery_profile) do
      {:ok, configuration} ->
        {:ok, configuration}

      {:error, message} ->
        # A provider-connects profile without usable egress addresses gets a named code (#990).
        case TCPSocket.egress_refusal(delivery_profile) do
          nil -> {:error, {:provider_delivery_profile_unusable, message}}
          code -> {:error, code}
        end
    end
  end

  defp provider_transport_basis(opts) do
    case Keyword.fetch(opts, :provider_transport_basis) do
      {:ok, %ProviderTransportBasis{} = basis} -> {:ok, basis}
      _missing_or_invalid -> {:error, :provider_transport_basis_required}
    end
  end

  defp require_provider_scope(transport, provider, provider_id) do
    if provider.organization_id == transport.organization_id and
         provider.mission_id == transport.mission_id and provider.provider_id == provider_id do
      :ok
    else
      {:error, :mission_provider_configuration_scope_mismatch}
    end
  end

  defp require_validated_provider(%ProviderTransportBasis{} = provider) do
    cond do
      provider.lifecycle_state != :active ->
        {:error, :mission_provider_not_active}

      not match?(%DateTime{}, provider.last_validated_at) ->
        {:error, :mission_provider_not_validated}

      provider.control_status != "healthy" ->
        {:error, :mission_provider_not_validated}

      not match?(%DateTime{}, provider.last_synced_at) ->
        {:error, :mission_provider_profiles_not_synced}

      true ->
        :ok
    end
  end

  defp find_profile(provider, document_key, reference) do
    with {:ok, id, version} <- profile_reference(reference),
         items when is_list(items) <-
           get_in(provider.inventory_sync_document, [document_key, "items"]),
         profile when is_map(profile) <-
           Enum.find(items, &(&1["id"] == id and &1["version"] == version)) do
      {:ok, profile}
    else
      _other -> {:error, {:provider_profile_not_found, document_key}}
    end
  end

  defp profile_reference(reference) when is_map(reference) do
    id = Map.get(reference, "id", Map.get(reference, :id))
    version = Map.get(reference, "version", Map.get(reference, :version))

    if is_binary(id) and id != "" and is_integer(version) and version > 0,
      do: {:ok, id, version},
      else: {:error, :invalid_provider_profile_reference}
  end

  defp profile_reference(_reference), do: {:error, :invalid_provider_profile_reference}

  defp require_profile_compatibility(service_profile, delivery_profile) do
    service_id = service_profile["id"]
    supported_services = delivery_profile["supported_service_profile_refs"] || []

    cond do
      service_profile["state"] != "active" ->
        {:error, :provider_service_profile_not_active}

      delivery_profile["state"] != "ready" ->
        {:error, :provider_delivery_profile_not_ready}

      not supported_directions?(service_profile["direction"], delivery_profile["direction"]) ->
        {:error, :provider_profile_direction_not_supported}

      service_id not in supported_services ->
        {:error, :provider_profiles_not_compatible}

      true ->
        :ok
    end
  end

  # A downlink delivery carries TM to Cadence; an uplink delivery (#44) is where the provider
  # connects to receive TC frames and return CLCWs.
  defp supported_directions?("downlink", "downlink"), do: true

  defp supported_directions?(service, "uplink") when service in ["uplink", "bidirectional"],
    do: true

  defp supported_directions?(_service, _delivery), do: false

  defp provider_direction_capability(%{"direction" => "uplink"}), do: :outbound
  defp provider_direction_capability(_delivery_profile), do: :inbound

  defp provider_snapshot(provider, service_profile, delivery_profile, configuration) do
    RedactedJson.sanitize(%{
      "provider" => %{
        "id" => provider.provider_id,
        "version" => provider.provider_version,
        "display_name" => provider.display_name,
        "provider_type" => Atom.to_string(provider.provider_type),
        "environment_ref" => provider.environment_ref
      },
      "service_profile" => service_profile,
      "delivery_profile" => delivery_profile,
      "derived_configuration" => configuration
    })
  end

  defp exact_profile_ref(profile),
    do: %{"id" => profile["id"], "version" => profile["version"]}

  defp direction_capability("inbound"), do: :inbound
  defp direction_capability("outbound"), do: :outbound
  defp direction_capability("bidirectional"), do: :bidirectional

  defp put_organization_scope(%Transport{} = transport, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case transport.organization_id do
      nil ->
        {:ok, %Transport{transport | organization_id: organization_id}}

      ^organization_id ->
        {:ok, transport}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          transport.mission_id}}
    end
  end
end
