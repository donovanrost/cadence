defmodule Cadence.Contacts.ProviderReservations do
  @moduledoc """
  Organization-scoped persistence and transition service for provider reservations.

  External calls deliberately do not live in this module. It provides the
  durable before/after boundary used by booking and reconciliation sagas.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.Contacts

  alias Cadence.Contacts.{
    KnownAtom,
    ProviderReservation,
    ProviderReservationChanges,
    ScheduledContact
  }

  alias Cadence.GroundNetworks.Validation
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.Schemas.ProviderReservationRow
  alias Cadence.Repo

  @document_byte_limit 65_536
  @nonterminal_states ~w(requesting pending confirmed active unknown canceling)
  @materialized_states [:confirmed, :active, :completed]

  @provider_states %{
    "scheduled" => :confirmed,
    "acquiring" => :confirmed,
    "terminated_early" => :failed,
    "requesting" => :requesting,
    "pending" => :pending,
    "confirmed" => :confirmed,
    "active" => :active,
    "completed" => :completed,
    "unknown" => :unknown,
    "rejected" => :rejected,
    "canceling" => :canceling,
    "canceled" => :canceled,
    "failed" => :failed
  }

  @allowed_transitions %{
    requesting: ~w(requesting pending confirmed active completed unknown rejected failed)a,
    pending: ~w(pending confirmed active completed unknown rejected failed canceling canceled)a,
    confirmed: ~w(confirmed active completed unknown canceling canceled failed)a,
    active: ~w(active completed unknown canceling canceled failed)a,
    unknown: ~w(unknown pending confirmed active completed rejected failed canceling canceled)a,
    canceling: ~w(canceling canceled unknown failed completed active confirmed)a,
    completed: [:completed],
    rejected: [:rejected],
    canceled: [:canceled],
    failed: [:failed]
  }

  @spec create_attempt(binary(), ProviderReservation.t() | map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def create_attempt(organization_id, attrs) when is_binary(organization_id) do
    case create_attempt_with_outcome(organization_id, attrs) do
      {:ok, reservation, _outcome} -> {:ok, reservation}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec create_attempt_with_outcome(binary(), ProviderReservation.t() | map()) ::
          {:ok, ProviderReservation.t(), :created | :existing} | {:error, term()}
  def create_attempt_with_outcome(organization_id, attrs) when is_binary(organization_id) do
    with {:ok, reservation} <- prepare_reservation(organization_id, attrs),
         {:ok, _mission} <- Missions.fetch_mission(organization_id, reservation.mission_id),
         :ok <- validate_documents(reservation) do
      case Repo.insert(ProviderReservationRow.changeset(reservation)) do
        {:ok, row} ->
          {:ok, ProviderReservationRow.to_domain(row), :created}

        {:error, %Changeset{} = changeset} ->
          resolve_insert_conflict(organization_id, reservation, changeset)

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    error in [ArgumentError, KeyError] -> {:error, {:invalid_provider_reservation, error.message}}
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, :provider_reservation_not_found}
  def fetch(organization_id, mission_id, provider_reservation_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_reservation_id) do
    case Repo.get_by(ProviderReservationRow,
           organization_id: organization_id,
           mission_id: mission_id,
           provider_reservation_id: provider_reservation_id
         ) do
      nil -> {:error, :provider_reservation_not_found}
      row -> {:ok, ProviderReservationRow.to_domain(row)}
    end
  end

  @spec fetch_by_idempotency_key(binary(), binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, :provider_reservation_not_found}
  def fetch_by_idempotency_key(
        organization_id,
        mission_id,
        provider_id,
        idempotency_key
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_id) and is_binary(idempotency_key) do
    case Repo.get_by(ProviderReservationRow,
           organization_id: organization_id,
           mission_id: mission_id,
           provider_id: provider_id,
           idempotency_key: idempotency_key
         ) do
      nil -> {:error, :provider_reservation_not_found}
      row -> {:ok, ProviderReservationRow.to_domain(row)}
    end
  end

  @spec fetch_by_provider_contact_ref(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, :provider_reservation_not_found}
  def fetch_by_provider_contact_ref(organization_id, mission_id, provider_contact_ref)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_contact_ref) do
    case Repo.get_by(ProviderReservationRow,
           organization_id: organization_id,
           mission_id: mission_id,
           provider_contact_ref: provider_contact_ref
         ) do
      nil -> {:error, :provider_reservation_not_found}
      row -> {:ok, ProviderReservationRow.to_domain(row)}
    end
  end

  @doc "Resolves one event only inside its exact Provider Account version boundary."
  @spec resolve_provider_event(binary(), binary(), pos_integer(), binary() | nil, binary() | nil) ::
          {:ok, ProviderReservation.t()}
          | {:error, :provider_reservation_not_found | :provider_event_correlation_ambiguous}
  def resolve_provider_event(
        organization_id,
        provider_account_id,
        provider_account_version,
        resource_id,
        client_reference
      ) do
    correlation =
      dynamic(false)
      |> maybe_correlate(:provider_contact_ref, resource_id)
      |> maybe_correlate(:idempotency_key, client_reference)

    rows =
      ProviderReservationRow
      |> where(
        [row],
        row.organization_id == ^organization_id and
          row.provider_account_id == ^provider_account_id and
          row.provider_account_version == ^provider_account_version
      )
      |> where(^correlation)
      |> limit(2)
      |> Repo.all()

    case rows do
      [row] -> {:ok, ProviderReservationRow.to_domain(row)}
      [] -> {:error, :provider_reservation_not_found}
      [_first, _second] -> {:error, :provider_event_correlation_ambiguous}
    end
  end

  @spec list_for_mission(binary(), binary()) :: [ProviderReservation.t()]
  def list_for_mission(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ProviderReservationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], desc: row.starts_at, desc: row.provider_reservation_id)
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
  end

  @spec list_due_for_reconciliation(binary(), keyword()) :: [ProviderReservation.t()]
  def list_due_for_reconciliation(organization_id, opts)
      when is_binary(organization_id) and is_list(opts) do
    due_before = Keyword.get(opts, :due_before, DateTime.utc_now())
    limit = Keyword.get(opts, :limit, 100)

    ProviderReservationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.lifecycle_state in ^@nonterminal_states and
        (is_nil(row.last_reconciled_at) or row.last_reconciled_at <= ^due_before)
    )
    |> maybe_filter_mission(Keyword.get(opts, :mission_id))
    |> order_by([row], asc_nulls_first: row.last_reconciled_at, asc: row.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
  end

  @spec record_provider_response(binary(), binary(), binary(), map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def record_provider_response(organization_id, mission_id, provider_reservation_id, response)
      when is_map(response) do
    with {:ok, reservation} <- fetch(organization_id, mission_id, provider_reservation_id),
         :ok <- validate_document(response, :response_document),
         {:ok, reservation, initial_response?} <- observe_provider_revision(reservation, response),
         {:ok, lifecycle_state} <- normalized_lifecycle_state(response, reservation),
         {:ok, observations} <- provider_observations(response, reservation) do
      snapshot = ProviderReservationChanges.snapshot(response, reservation)

      transition(reservation, lifecycle_state, %{
        provider_contact_ref: provider_contact_ref(response, reservation),
        provider_revision: snapshot["provider_revision"],
        provider_status: provider_status(response),
        pass_phase: Atom.to_string(observations.pass_phase),
        delivery_state: Atom.to_string(observations.delivery_state),
        delivery_descriptor_document:
          JsonDocument.wrap_value(observations.delivery_descriptor_document),
        response_document: JsonDocument.wrap_value(response),
        provider_confirmed_snapshot_document: JsonDocument.wrap_value(snapshot),
        cadence_accepted_snapshot_document:
          accepted_snapshot(reservation, snapshot, initial_response?),
        last_error_document: JsonDocument.wrap_value(%{}),
        attempt_count: reservation.attempt_count + 1,
        last_reconciled_at: DateTime.utc_now()
      })
    end
  end

  @spec record_provider_error(binary(), binary(), binary(), map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def record_provider_error(organization_id, mission_id, provider_reservation_id, error_document)
      when is_map(error_document) do
    with {:ok, reservation} <- fetch(organization_id, mission_id, provider_reservation_id),
         :ok <- validate_document(error_document, :last_error_document) do
      requested_state =
        error_document
        |> Map.get("lifecycle_state", Map.get(error_document, :lifecycle_state, :unknown))
        |> normalize_state()

      transition(reservation, requested_state, %{
        last_error_document: JsonDocument.wrap_value(error_document),
        attempt_count: reservation.attempt_count + 1,
        last_reconciled_at: DateTime.utc_now()
      })
    end
  end

  @spec mark_canceling(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def mark_canceling(organization_id, mission_id, provider_reservation_id) do
    with {:ok, reservation} <- fetch(organization_id, mission_id, provider_reservation_id) do
      transition(reservation, :canceling, %{last_error_document: JsonDocument.wrap_value(%{})})
    end
  end

  @spec materialize_scheduled_contact(binary(), binary(), binary()) ::
          {:ok,
           %{
             provider_reservation: ProviderReservation.t(),
             scheduled_contact: ScheduledContact.t()
           }}
          | {:error, term()}
  def materialize_scheduled_contact(organization_id, mission_id, provider_reservation_id) do
    with {:ok, reservation} <- fetch(organization_id, mission_id, provider_reservation_id),
         :ok <- ensure_materializable(reservation) do
      Multi.new()
      |> Multi.run(:scheduled_contact, fn _repo, _changes ->
        ensure_scheduled_contact(reservation)
      end)
      |> Multi.run(:provider_reservation, fn repo, %{scheduled_contact: scheduled_contact} ->
        row =
          repo.get_by!(ProviderReservationRow,
            organization_id: organization_id,
            mission_id: mission_id,
            provider_reservation_id: provider_reservation_id
          )

        metadata =
          row.metadata
          |> JsonDocument.unwrap_value()
          |> Map.put("scheduled_contact_id", scheduled_contact.scheduled_contact_id)

        row
        |> ProviderReservationRow.transition_changeset(%{
          metadata: JsonDocument.wrap_value(metadata)
        })
        |> repo.update()
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{scheduled_contact: scheduled_contact, provider_reservation: row}} ->
          {:ok,
           %{
             provider_reservation: ProviderReservationRow.to_domain(row),
             scheduled_contact: scheduled_contact
           }}

        {:error, _operation, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @spec apply_provider_status(binary(), binary(), binary(), map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def apply_provider_status(organization_id, mission_id, provider_reservation_id, response)
      when is_map(response) do
    case record_provider_response(
           organization_id,
           mission_id,
           provider_reservation_id,
           response
         ) do
      {:ok, reservation} ->
        with :ok <- apply_contact_side_effect(reservation) do
          fetch(organization_id, mission_id, provider_reservation_id)
        end

      {:error, {:provider_configuration_mismatch, reason}} ->
        persist_configuration_failure(
          organization_id,
          mission_id,
          provider_reservation_id,
          reason
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_reservation(organization_id, %ProviderReservation{} = reservation) do
    if reservation.organization_id in [nil, organization_id] do
      {:ok, %ProviderReservation{reservation | organization_id: organization_id}}
    else
      {:error, :organization_scope_mismatch}
    end
  end

  defp prepare_reservation(organization_id, attrs) when is_map(attrs) do
    {:ok, attrs |> Map.put(:organization_id, organization_id) |> ProviderReservation.new()}
  end

  defp observe_provider_revision(reservation, response) do
    snapshot = ProviderReservationChanges.snapshot(response, reservation)

    if snapshot["provider_revision"] > reservation.provider_revision do
      case ProviderReservationChanges.observe(reservation, response) do
        {:ok, _change, updated} -> {:ok, updated, false}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, reservation, reservation.response_document == %{}}
    end
  end

  defp accepted_snapshot(_reservation, snapshot, true),
    do: JsonDocument.wrap_value(snapshot)

  defp accepted_snapshot(reservation, _snapshot, false),
    do: JsonDocument.wrap_value(reservation.cadence_accepted_snapshot_document)

  defp resolve_insert_conflict(organization_id, reservation, changeset) do
    case fetch_by_idempotency_key(
           organization_id,
           reservation.mission_id,
           reservation.provider_id,
           reservation.idempotency_key
         ) do
      {:ok, existing} ->
        if immutable_payload(existing) == immutable_payload(reservation) do
          {:ok, existing, :existing}
        else
          {:error, {:idempotency_conflict, existing.provider_reservation_id}}
        end

      {:error, :provider_reservation_not_found} ->
        {:error, changeset}
    end
  end

  defp immutable_payload(reservation) do
    Map.take(Map.from_struct(reservation), [
      :mission_id,
      :provider_id,
      :provider_version,
      :transport_id,
      :transport_version,
      :service_profile_ref,
      :delivery_profile_ref,
      :provider_profile_id,
      :provider_profile_version,
      :scheduled_contact_id,
      :provider_opportunity_ref,
      :idempotency_key,
      :spacecraft_id,
      :provider_spacecraft_ref,
      :source_endpoint_refs,
      :path_template_ids,
      :starts_at,
      :ends_at,
      :request_document
    ])
  end

  defp transition(%ProviderReservation{} = reservation, requested_state, attrs) do
    requested_state = normalize_state(requested_state)

    if requested_state in Map.fetch!(@allowed_transitions, reservation.lifecycle_state) do
      reservation.provider_reservation_id
      |> reservation_row(reservation.organization_id, reservation.mission_id)
      |> ProviderReservationRow.transition_changeset(
        Map.put(attrs, :lifecycle_state, Atom.to_string(requested_state))
      )
      |> Repo.update()
      |> case do
        {:ok, row} -> {:ok, ProviderReservationRow.to_domain(row)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error,
       {:invalid_provider_reservation_transition, reservation.lifecycle_state, requested_state}}
    end
  end

  defp reservation_row(provider_reservation_id, organization_id, mission_id) do
    Repo.get_by!(ProviderReservationRow,
      provider_reservation_id: provider_reservation_id,
      organization_id: organization_id,
      mission_id: mission_id
    )
  end

  defp normalized_lifecycle_state(response, reservation) do
    raw_status = Map.get(response, "status", Map.get(response, :status))

    case raw_status do
      nil -> {:error, {:malformed_provider_response, :status}}
      status -> provider_state(status, reservation.lifecycle_state)
    end
  end

  defp normalize_state(status) do
    case provider_state(status, nil) do
      {:ok, state} -> state
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  defp provider_state(status, _current_state) when is_atom(status) do
    {:ok, KnownAtom.provider_reservation_lifecycle_state!(status)}
  rescue
    ArgumentError -> {:error, {:unsupported_provider_status, status}}
  end

  defp provider_state(status, current_state) when is_binary(status) do
    case Map.fetch(@provider_states, status) do
      {:ok, state} -> {:ok, state}
      :error -> {:error, {:unsupported_provider_status, status, current_state}}
    end
  end

  defp provider_status(response) do
    case Map.get(response, "provider_status", Map.get(response, :provider_status)) ||
           Map.get(response, "status", Map.get(response, :status)) do
      status when is_atom(status) -> Atom.to_string(status)
      status -> status
    end
  end

  defp provider_contact_ref(response, reservation) do
    Map.get(response, "provider_contact_ref", Map.get(response, :provider_contact_ref)) ||
      Map.get(response, "id", Map.get(response, :id)) || reservation.provider_contact_ref
  end

  defp maybe_correlate(query, _field, value) when value in [nil, ""], do: query

  defp maybe_correlate(query, field, value),
    do: dynamic([row], ^query or field(row, ^field) == ^value)

  defp ensure_materializable(%ProviderReservation{lifecycle_state: state})
       when state in @materialized_states,
       do: :ok

  defp ensure_materializable(%ProviderReservation{lifecycle_state: state}),
    do: {:error, {:provider_reservation_not_confirmed, state}}

  defp ensure_scheduled_contact(reservation) do
    case Contacts.fetch_scheduled_contact(
           reservation.organization_id,
           reservation.mission_id,
           reservation.scheduled_contact_id
         ) do
      {:ok, scheduled_contact} ->
        if scheduled_contact.provider_contact_ref == reservation.provider_contact_ref do
          {:ok, scheduled_contact}
        else
          {:error, :scheduled_contact_reservation_conflict}
        end

      {:error, :scheduled_contact_not_found} ->
        Contacts.persist_scheduled_contact(
          reservation.organization_id,
          ScheduledContact.new(%{
            organization_id: reservation.organization_id,
            mission_id: reservation.mission_id,
            scheduled_contact_id: reservation.scheduled_contact_id,
            source_endpoint_refs: reservation.source_endpoint_refs,
            contact_intents: [:telemetry_downlink],
            path_template_ids: reservation.path_template_ids,
            path_template_refs: path_template_refs(reservation),
            starts_at: reservation.starts_at,
            ends_at: reservation.ends_at,
            provider_contact_ref: reservation.provider_contact_ref,
            metadata: %{
              "provider_reservation_id" => reservation.provider_reservation_id,
              "provider_id" => reservation.provider_id,
              "provider_version" => reservation.provider_version,
              "transport_id" => reservation.transport_id,
              "transport_version" => reservation.transport_version,
              "service_profile_ref" => reservation.service_profile_ref,
              "delivery_profile_ref" => reservation.delivery_profile_ref,
              "provider_profile_id" => reservation.provider_profile_id,
              "provider_profile_version" => reservation.provider_profile_version
            }
          })
        )
    end
  end

  defp path_template_refs(reservation) do
    case get_in(reservation.request_document, ["routing", "path_template_refs"]) do
      refs when is_list(refs) ->
        refs

      _other ->
        Enum.map(reservation.path_template_ids, &%{"path_template_id" => &1, "version" => 1})
    end
  end

  defp apply_contact_side_effect(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in @materialized_states do
    case materialize_scheduled_contact(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_reservation_id
         ) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_contact_side_effect(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in [:canceled, :failed] do
    case Contacts.fetch_scheduled_contact(
           reservation.organization_id,
           reservation.mission_id,
           reservation.scheduled_contact_id
         ) do
      {:ok, %ScheduledContact{lifecycle_state: :scheduled}} ->
        case Contacts.cancel_scheduled_contact(
               reservation.organization_id,
               reservation.mission_id,
               reservation.scheduled_contact_id,
               actor: %{"kind" => "system", "id" => "provider_reservation_reconciler"},
               reason: "provider_#{state}"
             ) do
          {:ok, _contact} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _contact} ->
        :ok

      {:error, :scheduled_contact_not_found} ->
        :ok
    end
  end

  defp apply_contact_side_effect(_reservation), do: :ok

  defp validate_documents(reservation) do
    with :ok <- validate_document(reservation.request_document, :request_document),
         :ok <- validate_document(reservation.response_document, :response_document),
         :ok <-
           validate_document(
             reservation.requested_snapshot_document,
             :requested_snapshot_document
           ),
         :ok <-
           validate_document(
             reservation.provider_confirmed_snapshot_document,
             :provider_confirmed_snapshot_document
           ),
         :ok <-
           validate_document(
             reservation.cadence_accepted_snapshot_document,
             :cadence_accepted_snapshot_document
           ),
         :ok <- validate_document(reservation.last_error_document, :last_error_document),
         :ok <-
           validate_document(
             reservation.delivery_descriptor_document,
             :delivery_descriptor_document
           ),
         :ok <- validate_document(reservation.service_profile_ref, :service_profile_ref),
         :ok <- validate_document(reservation.delivery_profile_ref, :delivery_profile_ref) do
      validate_document(reservation.metadata, :metadata)
    end
  end

  defp provider_observations(response, reservation) do
    with :ok <- validate_response_bindings(response, reservation),
         {:ok, pass_phase} <- pass_phase(response, reservation),
         {:ok, delivery_state} <- delivery_state(response, reservation),
         {:ok, descriptor_document} <- delivery_descriptor(response, reservation) do
      {:ok,
       %{
         pass_phase: pass_phase,
         delivery_state: delivery_state,
         delivery_descriptor_document: descriptor_document
       }}
    end
  end

  defp validate_response_bindings(response, reservation) do
    checks = [
      {"client_reference", reservation.idempotency_key},
      {"opportunity_ref", reservation.provider_opportunity_ref},
      {"spacecraft_ref", reservation.provider_spacecraft_ref},
      {"service_profile_ref", reservation.service_profile_ref["id"]},
      {"delivery_profile_ref", reservation.delivery_profile_ref["id"]}
    ]

    case Enum.find(checks, fn {key, expected} ->
           value = Map.get(response, key)
           not is_nil(value) and value != expected
         end) do
      nil -> :ok
      {key, _expected} -> {:error, {:provider_configuration_mismatch, {:contact_binding, key}}}
    end
  end

  defp pass_phase(response, reservation) do
    response
    |> Map.get("pass_phase", Atom.to_string(reservation.pass_phase))
    |> then(&{:ok, KnownAtom.provider_pass_phase!(&1)})
  rescue
    ArgumentError -> {:error, {:malformed_provider_response, :pass_phase}}
  end

  defp delivery_state(response, reservation) do
    response
    |> Map.get("delivery_state", Atom.to_string(reservation.delivery_state))
    |> then(&{:ok, KnownAtom.provider_delivery_state!(&1)})
  rescue
    ArgumentError -> {:error, {:malformed_provider_response, :delivery_state}}
  end

  defp delivery_descriptor(%{"delivery_descriptor" => descriptor}, reservation)
       when is_map(descriptor) do
    descriptor = Validation.sanitize(descriptor)

    with {:ok, %Transport{} = transport} <-
           TransportStore.fetch_transport_version(
             reservation.organization_id,
             reservation.mission_id,
             reservation.transport_id,
             reservation.transport_version
           ),
         :ok <- validate_transport_binding(transport, reservation),
         :ok <- validate_descriptor_binding(descriptor, transport, reservation),
         document = immutable_descriptor_document(descriptor),
         :ok <- validate_immutable_descriptor(document, reservation) do
      {:ok, document}
    else
      {:error, reason} -> {:error, {:provider_configuration_mismatch, reason}}
    end
  end

  defp delivery_descriptor(_response, reservation),
    do: {:ok, reservation.delivery_descriptor_document}

  defp validate_transport_binding(transport, reservation) do
    cond do
      transport.origin != :provider_managed ->
        {:error, :transport_not_provider_managed}

      transport.mission_provider_id != reservation.provider_id or
          transport.mission_provider_version != reservation.provider_version ->
        {:error, :transport_provider_binding_changed}

      transport.service_profile_ref != reservation.service_profile_ref or
          transport.delivery_profile_ref != reservation.delivery_profile_ref ->
        {:error, :transport_profile_binding_changed}

      true ->
        :ok
    end
  end

  defp validate_descriptor_binding(descriptor, transport, reservation) do
    delivery_profile =
      get_in(transport.provider_configuration_snapshot, ["delivery_profile"]) || %{}

    diagnostics = Map.get(delivery_profile, "diagnostics", %{})
    framing = Map.get(descriptor, "framing", %{})
    activation_window = Map.get(descriptor, "activation_window", %{})

    checks = [
      descriptor["direction"] == "downlink",
      descriptor["delivery_kind"] == delivery_profile["delivery_kind"],
      descriptor["mode"] == diagnostics["mode"],
      descriptor["protocol"] == diagnostics["protocol"],
      descriptor["endpoint_ref"] == reservation.delivery_profile_ref["id"],
      framing["family"] == diagnostics["framing_family"],
      framing["frame_bytes"] == diagnostics["frame_bytes"],
      reservation.provider_spacecraft_ref in (descriptor["allowed_source_refs"] || []),
      activation_covers?(activation_window, reservation)
    ]

    if Enum.all?(checks),
      do: :ok,
      else: {:error, :delivery_descriptor_conflicts_with_transport}
  end

  defp activation_covers?(window, reservation) do
    with {:ok, starts_at, _offset} <- DateTime.from_iso8601(window["starts_at"] || ""),
         {:ok, ends_at, _offset} <- DateTime.from_iso8601(window["ends_at"] || "") do
      DateTime.compare(starts_at, reservation.starts_at) in [:lt, :eq] and
        DateTime.compare(ends_at, reservation.ends_at) in [:gt, :eq]
    else
      _error -> false
    end
  end

  defp immutable_descriptor_document(descriptor) do
    Map.drop(descriptor, ["status", "reason", "diagnostics"])
  end

  defp validate_immutable_descriptor(document, %{delivery_descriptor_document: existing})
       when existing == %{},
       do: validate_document(document, :delivery_descriptor_document)

  defp validate_immutable_descriptor(document, %{delivery_descriptor_document: document}), do: :ok

  defp validate_immutable_descriptor(_document, _reservation),
    do: {:error, :delivery_descriptor_changed}

  defp persist_configuration_failure(organization_id, mission_id, reservation_id, reason) do
    error_document = %{
      "lifecycle_state" => "failed",
      "category" => "provider_configuration_failure",
      "reason" => JsonDocument.encode(reason),
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "provider_reservation_validation"
    }

    case record_provider_error(
           organization_id,
           mission_id,
           reservation_id,
           error_document
         ) do
      {:ok, failed} -> {:error, {:provider_configuration_failure, failed, reason}}
      {:error, persistence_reason} -> {:error, persistence_reason}
    end
  end

  defp validate_document(document, field) when is_map(document) do
    case Jason.encode(document) do
      {:ok, json} when byte_size(json) <= @document_byte_limit -> :ok
      {:ok, _json} -> {:error, {:provider_reservation_document_too_large, field}}
      {:error, reason} -> {:error, {:invalid_provider_reservation_document, field, reason}}
    end
  end

  defp validate_document(_document, field),
    do: {:error, {:invalid_provider_reservation_document, field}}

  defp maybe_filter_mission(query, nil), do: query

  defp maybe_filter_mission(query, mission_id) when is_binary(mission_id) do
    where(query, [row], row.mission_id == ^mission_id)
  end
end
