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
  alias Cadence.ContactPlanning.BookingOutcomes
  alias Cadence.Contacts

  alias Cadence.Contacts.{
    BookingResolutions,
    KnownAtom,
    ProviderReservation,
    ProviderReservationChanges,
    ReservationChange,
    ScheduledContact,
    UplinkLegs
  }

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.GroundNetworks.Validation
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  alias Cadence.Platform.{ContentHash, ResolutionEvidence}

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

  @spec mark_provider_grant_for_review(map(), DateTime.t()) :: {:ok, non_neg_integer()}
  def mark_provider_grant_for_review(grant, %DateTime{} = now) when is_map(grant) do
    metadata_patch = %{
      "provider_grant_review" => %{
        "grant_id" => grant.provider_account_grant_id,
        "grant_version" => grant.version,
        "reason" => grant.revoke_reason,
        "recorded_at" => DateTime.to_iso8601(now)
      }
    }

    {count, _rows} =
      ProviderReservationRow
      |> where(
        [row],
        row.organization_id == ^grant.organization_id and row.mission_id == ^grant.mission_id and
          row.provider_account_grant_id == ^grant.provider_account_grant_id and
          row.lifecycle_state in ^@nonterminal_states
      )
      |> Repo.update_all(set: [operator_review_document: JsonDocument.wrap_value(metadata_patch)])

    if count > 0,
      do: ScopedReadUpdates.publish(:contacts_changed, grant.organization_id, grant.mission_id)

    {:ok, count}
  end

  # Console read invalidation (`:contacts_changed`) after a reservation write commits.
  # `ScopedReadUpdates` skips publishing inside a transaction, so a write nested in a caller's
  # transaction never announces a change that may still roll back.
  defp published({:ok, _} = result, organization_id, mission_id) do
    ScopedReadUpdates.publish(:contacts_changed, organization_id, mission_id)
    result
  end

  defp published(result, _organization_id, _mission_id), do: result

  defp published_reservation({:ok, %{mission_id: mission_id}, _outcome} = result, organization_id) do
    ScopedReadUpdates.publish(:contacts_changed, organization_id, mission_id)
    result
  end

  defp published_reservation(result, _organization_id), do: result

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

  @doc "Reviews the original reservation identity and recorded resolution evidence."
  def review_resolution(org, mission, id) do
    with {:ok, reservation} <- fetch(org, mission, id) do
      {:ok, resolution_summary(reservation, "review")}
    end
  end

  @doc "Resolves durable reservation evidence without making a provider mutation."
  def resolve_attempt(org, mission, id, evidence) do
    published(resolve_attempt_unpublished(org, mission, id, evidence), org, mission)
  end

  defp resolve_attempt_unpublished(org, mission, id, evidence) do
    Repo.transaction(fn -> resolve_attempt_locked(org, mission, id, evidence) end)
  end

  defp resolve_attempt_locked(org, mission, id, evidence) do
    row =
      Repo.one(
        from(r in ProviderReservationRow,
          where:
            r.organization_id == ^org and r.mission_id == ^mission and
              r.provider_reservation_id == ^id,
          lock: "FOR UPDATE"
        )
      )

    if is_nil(row), do: Repo.rollback(:provider_reservation_not_found)
    reservation = ProviderReservationRow.to_domain(row)

    if resolution_basis(reservation) != evidence["basis_sha256"],
      do: Repo.rollback(:provider_resolution_basis_changed)

    case ResolutionEvidence.existing(row.resolution_evidence, evidence) do
      {:ok, entry} ->
        resolution_summary(reservation, entry["disposition"])

      {:error, reason} ->
        Repo.rollback(reason)

      :new ->
        disposition = resolve_reservation_outcome(reservation, evidence)
        row = reservation_row(id, org, mission)

        with {:ok, log} <-
               ResolutionEvidence.append(row.resolution_evidence, evidence, disposition),
             {:ok, row} <- Repo.update(Changeset.change(row, resolution_evidence: log)) do
          resolution_summary(ProviderReservationRow.to_domain(row), disposition)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp resolution_summary(reservation, disposition),
    do: %{
      basis_sha256: resolution_basis(reservation),
      reservation: reservation,
      disposition: disposition
    }

  defp resolution_basis(reservation) do
    reservation
    |> Map.from_struct()
    |> Map.drop([
      :lifecycle_state,
      :provider_status,
      :provider_contact_ref,
      :provider_revision,
      :pass_phase,
      :delivery_state,
      :delivery_descriptor_document,
      :response_document,
      :provider_confirmed_snapshot_document,
      :cadence_accepted_snapshot_document,
      :last_error_document,
      :operator_review_document,
      :attempt_count,
      :last_reconciled_at,
      :metadata,
      :resolution_evidence,
      :inserted_at,
      :updated_at
    ])
    |> ContentHash.term_sha256()
  end

  defp resolve_reservation_outcome(%{lifecycle_state: state}, evidence)
       when state in [:confirmed, :active, :completed, :canceled, :rejected, :failed] do
    positive? = state in [:confirmed, :active, :completed]

    contradiction? =
      (positive? and evidence["outcome"] in ~w(not_sent rejected)) or
        (not positive? and evidence["outcome"] == "accepted")

    if contradiction?, do: "contradictory", else: "retained_terminal"
  end

  defp resolve_reservation_outcome(reservation, %{"outcome" => "unknown"}) do
    if reservation.lifecycle_state == :requesting,
      do: checked_resolution(transition(reservation, :unknown, %{}))

    "held_unknown"
  end

  defp resolve_reservation_outcome(reservation, %{"outcome" => "accepted"} = evidence) do
    response = evidence["provider_response"] || %{}

    unless correlated_provider_response?(reservation, response),
      do: Repo.rollback(:provider_resolution_correlation_mismatch)

    unless response["status"] in ~w(pending confirmed scheduled acquiring active completed canceled),
      do: Repo.rollback(:provider_resolution_status_mismatch)

    checked_resolution(
      apply_provider_status(
        reservation.organization_id,
        reservation.mission_id,
        reservation.provider_reservation_id,
        response
      )
    )

    "accepted"
  end

  defp resolve_reservation_outcome(reservation, evidence) do
    # A failed cancellation is not a failed booking. Existing provider contact
    # evidence requires a correlated provider status before changing its state.
    if reservation.provider_contact_ref || reservation.lifecycle_state in [:pending, :canceling] ||
         reservation.provider_confirmed_snapshot_document["status"] in ~w(pending confirmed active completed canceling canceled) do
      "held_provider_status_required"
    else
      state = if evidence["outcome"] == "rejected", do: :rejected, else: :failed

      checked_resolution(
        transition(reservation, state, %{
          last_error_document:
            JsonDocument.wrap_value(%{
              "source" => "attempt_resolution",
              "reason" => evidence["outcome"],
              # ux U29 "by <name> at <time>": who recorded the evidence, and when.
              "resolved_by" => Map.take(evidence["actor"] || %{}, ["kind", "id"]),
              "resolved_at" => evidence["recorded_at"]
            })
        })
      )

      "closed_without_resend"
    end
  end

  defp correlated_provider_response?(reservation, response) do
    references = [
      {response["client_reference"], reservation.idempotency_key},
      {response["provider_contact_ref"] || response["id"], reservation.provider_contact_ref}
    ]

    Enum.any?(references, fn {observed, expected} ->
      is_binary(observed) and is_binary(expected) and observed == expected
    end) and
      Enum.all?(references, fn {observed, expected} ->
        is_nil(observed) or is_nil(expected) or observed == expected
      end)
  end

  defp checked_resolution({:ok, result}), do: result
  defp checked_resolution({:error, reason}), do: Repo.rollback(reason)

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
    organization_id
    |> create_attempt_with_outcome_unpublished(attrs)
    |> published_reservation(organization_id)
  end

  defp create_attempt_with_outcome_unpublished(organization_id, attrs) do
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

  @doc "A bounded current reservation ledger page inside its mission."
  def list_mission_page(org, mission, page) when is_integer(page) and page in 1..1_000_000 do
    rows =
      ProviderReservationRow
      |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
      |> order_by([r], desc: r.starts_at, desc: r.provider_reservation_id)
      |> offset(^((page - 1) * 25))
      |> limit(26)
      |> Repo.all()

    {:ok,
     %{
       page: page,
       more: length(rows) > 25,
       entries: rows |> Enum.take(25) |> Enum.map(&ProviderReservationRow.to_domain/1)
     }}
  end

  @doc """
  Reservations whose window overlaps `[from, to)`, oldest start first, at most
  `:limit` (default 500). Returns `{entries, truncated?}`. Option
  `:spacecraft_id` narrows to one spacecraft.
  """
  @spec list_in_window(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {[ProviderReservation.t()], boolean()}
  def list_in_window(org, mission, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    rows =
      ProviderReservationRow
      |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
      |> where([r], r.starts_at < ^to and r.ends_at > ^from)
      |> window_spacecraft(Keyword.get(opts, :spacecraft_id))
      |> order_by([r], asc: r.starts_at, asc: r.provider_reservation_id)
      |> limit(^(limit + 1))
      |> Repo.all()

    {rows |> Enum.take(limit) |> Enum.map(&ProviderReservationRow.to_domain/1),
     length(rows) > limit}
  end

  @booked_states ~w(confirmed active completed)
  @upcoming_states ~w(confirmed active)
  @dead_states ~w(rejected canceling canceled failed)

  @doc """
  Per-spacecraft contact facts at `now` from booked reservations:
  `%{tracked?: bool, passes_next_2h: n, by_spacecraft: %{id => %{in_contact,
  next_aos_at, last_los_at}}}`. `tracked?` is `false` when the mission has no
  reservations at all, so callers can say "not tracked" instead of "no contact".
  """
  @spec contact_summary(binary(), binary(), DateTime.t()) :: map()
  def contact_summary(org, mission, %DateTime{} = now) do
    base =
      where(ProviderReservationRow, [r], r.organization_id == ^org and r.mission_id == ^mission)

    if Repo.exists?(base) do
      in_contact =
        base
        |> where([r], r.starts_at <= ^now and r.ends_at > ^now)
        |> where([r], r.lifecycle_state == "active" or r.pass_phase == "pass")
        |> where([r], r.lifecycle_state not in @dead_states)
        |> distinct(true)
        |> select([r], r.spacecraft_id)
        |> Repo.all()
        |> MapSet.new()

      next =
        base
        |> where([r], r.starts_at > ^now and r.lifecycle_state in @upcoming_states)
        |> group_by([r], r.spacecraft_id)
        |> select([r], {r.spacecraft_id, min(r.starts_at)})
        |> Repo.all()
        |> Map.new()

      last =
        base
        |> where([r], r.ends_at <= ^now and r.lifecycle_state in @booked_states)
        |> group_by([r], r.spacecraft_id)
        |> select([r], {r.spacecraft_id, max(r.ends_at)})
        |> Repo.all()
        |> Map.new()

      soon = DateTime.add(now, 2 * 3_600)

      passes_next_2h =
        base
        |> where([r], r.starts_at > ^now and r.starts_at <= ^soon)
        |> where([r], r.lifecycle_state in @upcoming_states)
        |> Repo.aggregate(:count)

      ids =
        in_contact
        |> MapSet.to_list()
        |> Enum.concat(Map.keys(next))
        |> Enum.concat(Map.keys(last))

      %{
        tracked?: true,
        passes_next_2h: passes_next_2h,
        by_spacecraft:
          ids
          |> Enum.uniq()
          |> Map.new(fn id ->
            {id,
             %{
               in_contact: MapSet.member?(in_contact, id),
               next_aos_at: Map.get(next, id),
               last_los_at: Map.get(last, id)
             }}
          end)
      }
    else
      %{tracked?: false, passes_next_2h: nil, by_spacecraft: %{}}
    end
  end

  defp window_spacecraft(query, nil), do: query
  defp window_spacecraft(query, id), do: where(query, [r], r.spacecraft_id == ^id)

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
    before =
      ReservationChange.visible(fetch(organization_id, mission_id, provider_reservation_id))

    organization_id
    |> record_provider_response_unpublished(mission_id, provider_reservation_id, response)
    |> ReservationChange.publish_if_changed(organization_id, mission_id, before)
  end

  defp record_provider_response_unpublished(
         organization_id,
         mission_id,
         provider_reservation_id,
         response
       ) do
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
        last_error_document: JsonDocument.wrap_value(status_error(lifecycle_state, response)),
        attempt_count: reservation.attempt_count + 1,
        last_reconciled_at: DateTime.utc_now()
      })
    end
  end

  # A provider that turns a booking down by status (2xx, status rejected/failed/terminated_early)
  # keeps its reason, in the error path's shape (`reason.category`, `reason.detail`), so the plan
  # item and the console can say why (api 2026-11-13). Any other status clears the error.
  defp status_error(state, response) when state in [:rejected, :failed] do
    status = to_string(Map.get(response, "status", Map.get(response, :status)))

    case Map.get(response, "status_reason") do
      %{} = reason ->
        %{
          "reason" => %{
            "category" => reason["category"] || status,
            "detail" => reason["detail"] || reason["message"]
          }
        }

      reason ->
        %{"reason" => %{"category" => status, "detail" => if(is_binary(reason), do: reason)}}
    end
  end

  defp status_error(_state, _response), do: %{}

  @spec record_provider_error(binary(), binary(), binary(), map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def record_provider_error(organization_id, mission_id, provider_reservation_id, error_document)
      when is_map(error_document) do
    before =
      ReservationChange.visible(fetch(organization_id, mission_id, provider_reservation_id))

    organization_id
    |> record_provider_error_unpublished(mission_id, provider_reservation_id, error_document)
    |> ReservationChange.publish_if_changed(organization_id, mission_id, before)
  end

  defp record_provider_error_unpublished(
         organization_id,
         mission_id,
         provider_reservation_id,
         error_document
       ) do
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

  @doc """
  Records an operator's attestation that the provider booked this reservation (DECISIONS
  #53) and materializes its scheduled contact. The lifecycle stays the provider's.
  """
  @spec attest_booking(ProviderReservation.t(), map()) :: {:ok, map()} | {:error, term()}
  def attest_booking(%ProviderReservation{} = reservation, document) do
    with {:ok, _} <- put_operator_resolution(reservation, document) do
      materialize_scheduled_contact(
        reservation.organization_id,
        reservation.mission_id,
        reservation.provider_reservation_id
      )
    end
  end

  @doc "Marks a reservation with an operator resolution (#53); its lifecycle is unchanged."
  @spec put_operator_resolution(ProviderReservation.t(), map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def put_operator_resolution(%ProviderReservation{} = reservation, document) do
    row =
      reservation_row(
        reservation.provider_reservation_id,
        reservation.organization_id,
        reservation.mission_id
      )

    metadata =
      row.metadata
      |> JsonDocument.unwrap_value()
      |> Kernel.||(%{})
      |> Map.put("operator_resolution", document)

    row
    |> ProviderReservationRow.transition_changeset(%{metadata: JsonDocument.wrap_value(metadata)})
    |> Repo.update()
    |> case do
      {:ok, row} -> {:ok, ProviderReservationRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attested?(%ProviderReservation{
         metadata: %{"operator_resolution" => %{"action" => "booked"}}
       }),
       do: true

  defp attested?(_reservation), do: false

  @doc """
  A cancel that failed, never read as a lost booking (rejected/failed). The error is the
  reservation's `last_error` (`"action" => "cancel"`). `"outcome" => "refused"` or `"not_sent"`:
  the cancel didn't happen, so the reservation goes back to the state it was canceled from and
  isn't marked a Cadence cancellation. `"unknown"`: it reads `unknown` for the reconciler's next
  read to settle; if the booking turns out gone, the cancellation was ours.
  """
  @spec cancel_failed(ProviderReservation.t(), map()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def cancel_failed(%ProviderReservation{} = reservation, error_document) do
    %{organization_id: org, mission_id: mission} = reservation
    published(cancel_failed_unpublished(reservation, error_document), org, mission)
  end

  defp cancel_failed_unpublished(reservation, error_document) do
    with {:ok, current} <-
           fetch(
             reservation.organization_id,
             reservation.mission_id,
             reservation.provider_reservation_id
           ),
         :ok <- validate_document(error_document, :last_error_document) do
      metadata = JsonDocument.unwrap_value(current.metadata) || %{}
      happened? = error_document["outcome"] == "unknown"

      restored =
        if happened?,
          do: :unknown,
          else: normalize_state(metadata["cancel_from_state"] || "confirmed")

      metadata =
        if happened?,
          do: metadata,
          else: Map.drop(metadata, ["cancel_initiator", "cancel_requested_at"])

      # Durable, unlike last_error (the next provider read clears it): the pass_release
      # attention item stays open until the booking is canceled or the pass ends.
      failure = Map.take(error_document, ["outcome", "reason", "recorded_at"])

      metadata =
        metadata
        |> Map.delete("cancel_from_state")
        |> Map.put("cancel_failure", failure)

      with {:ok, _} = result <-
             transition(current, restored, %{
               last_error_document: JsonDocument.wrap_value(error_document),
               attempt_count: current.attempt_count + 1,
               last_reconciled_at: DateTime.utc_now(),
               metadata: JsonDocument.wrap_value(metadata)
             }) do
        ScopedReadUpdates.publish(:attention_changed, current.organization_id, current.mission_id)
        result
      end
    end
  end

  @spec mark_canceling(binary(), binary(), binary(), keyword()) ::
          {:ok, ProviderReservation.t()} | {:error, term()}
  def mark_canceling(org, mission, id, opts \\ []) do
    published(mark_canceling_unpublished(org, mission, id, opts), org, mission)
  end

  defp mark_canceling_unpublished(org, mission, id, opts) do
    Repo.transaction(fn ->
      row =
        ProviderReservationRow
        |> where(
          [r],
          r.organization_id == ^org and r.mission_id == ^mission and
            r.provider_reservation_id == ^id
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %ProviderReservationRow{} <- row,
           :ok <- reviewed_cancellation(row, Keyword.get(opts, :expected_cancel_evidence)),
           {:ok, reservation} <-
             transition(ProviderReservationRow.to_domain(row), :canceling, %{
               last_error_document: JsonDocument.wrap_value(%{}),
               metadata: cadence_initiated(row)
             }) do
        reservation
      else
        nil -> Repo.rollback(:provider_reservation_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Pass review (S9, DECISIONS #47) tells Cadence-requested cancellations from provider ones.
  defp cadence_initiated(row) do
    row.metadata
    |> JsonDocument.unwrap_value()
    |> Kernel.||(%{})
    |> Map.merge(%{
      "cancel_initiator" => "cadence",
      "cancel_requested_at" => DateTime.to_iso8601(DateTime.utc_now()),
      # A failed cancel puts the reservation back where it was.
      "cancel_from_state" => row.lifecycle_state
    })
    |> JsonDocument.wrap_value()
  end

  defp reviewed_cancellation(_, nil), do: :ok

  defp reviewed_cancellation(row, evidence) do
    current = %{
      "provider_revision" => row.provider_revision,
      "lifecycle_state" => row.lifecycle_state,
      "provider_contact_ref" => row.provider_contact_ref
    }

    if current === evidence and row.lifecycle_state in ~w(pending confirmed active),
      do: :ok,
      else: {:error, :stale_reservation_cancellation_evidence}
  end

  @spec materialize_scheduled_contact(binary(), binary(), binary()) ::
          {:ok,
           %{
             provider_reservation: ProviderReservation.t(),
             scheduled_contact: ScheduledContact.t()
           }}
          | {:error, term()}
  def materialize_scheduled_contact(organization_id, mission_id, provider_reservation_id) do
    organization_id
    |> materialize_scheduled_contact_unpublished(mission_id, provider_reservation_id)
    |> published(organization_id, mission_id)
  end

  defp materialize_scheduled_contact_unpublished(
         organization_id,
         mission_id,
         provider_reservation_id
       ) do
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
    # A poll that changed nothing visible announces nothing (qa 11-14, ReservationChange).
    before =
      ReservationChange.visible(fetch(organization_id, mission_id, provider_reservation_id))

    organization_id
    |> apply_provider_status_unpublished(mission_id, provider_reservation_id, response)
    |> ReservationChange.publish_if_changed(organization_id, mission_id, before)
  end

  defp apply_provider_status_unpublished(
         organization_id,
         mission_id,
         provider_reservation_id,
         response
       ) do
    # Unpublished: apply_provider_status announces once, and only on a visible change.
    case record_provider_response_unpublished(
           organization_id,
           mission_id,
           provider_reservation_id,
           response
         ) do
      {:ok, reservation} ->
        with :ok <- apply_contact_side_effect(reservation),
             :ok <- BookingResolutions.provider_answered(reservation) do
          fetch(organization_id, mission_id, provider_reservation_id)
        end

      {:error, {:invalid_provider_reservation_transition, :canceled, requested}} = error ->
        BookingResolutions.provider_answer_refused(
          organization_id,
          mission_id,
          provider_reservation_id,
          requested
        )

        error

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
    |> Map.update!(:starts_at, &DateTime.to_unix(&1, :microsecond))
    |> Map.update!(:ends_at, &DateTime.to_unix(&1, :microsecond))
  end

  defp transition(%ProviderReservation{} = reservation, requested_state, attrs) do
    requested_state = normalize_state(requested_state)

    Repo.transaction(fn -> transition_locked(reservation, requested_state, attrs) end)
  end

  defp transition_locked(reservation, requested_state, attrs) do
    row =
      Repo.one!(
        from(r in ProviderReservationRow,
          where:
            r.organization_id == ^reservation.organization_id and
              r.mission_id == ^reservation.mission_id and
              r.provider_reservation_id == ^reservation.provider_reservation_id,
          lock: "FOR UPDATE"
        )
      )

    current = ProviderReservationRow.to_domain(row)

    stable = fn value ->
      Map.drop(Map.from_struct(value), [:resolution_evidence, :inserted_at, :updated_at])
    end

    cond do
      stable.(current) != stable.(reservation) ->
        Repo.rollback(:provider_reservation_changed)

      requested_state not in Map.fetch!(@allowed_transitions, current.lifecycle_state) ->
        Repo.rollback(
          {:invalid_provider_reservation_transition, current.lifecycle_state, requested_state}
        )

      true ->
        case Repo.update(
               ProviderReservationRow.transition_changeset(
                 row,
                 Map.put(attrs, :lifecycle_state, Atom.to_string(requested_state))
               )
             ) do
          {:ok, row} -> ProviderReservationRow.to_domain(row)
          {:error, reason} -> Repo.rollback(reason)
        end
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

  # An operator attested the booking while the provider stayed silent (DECISIONS #53).
  defp ensure_materializable(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in [:pending, :unknown] do
    if attested?(reservation),
      do: :ok,
      else: {:error, {:provider_reservation_not_confirmed, state}}
  end

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
        {uplink_ids, uplink_refs, intents, uplink_metadata} =
          UplinkLegs.scheduled_fields(reservation)

        Contacts.persist_scheduled_contact(
          reservation.organization_id,
          ScheduledContact.new(%{
            organization_id: reservation.organization_id,
            mission_id: reservation.mission_id,
            scheduled_contact_id: reservation.scheduled_contact_id,
            source_endpoint_refs: reservation.source_endpoint_refs,
            contact_intents: intents,
            path_template_ids: reservation.path_template_ids ++ uplink_ids,
            path_template_refs: path_template_refs(reservation) ++ uplink_refs,
            starts_at: reservation.starts_at,
            ends_at: reservation.ends_at,
            provider_contact_ref: reservation.provider_contact_ref,
            metadata:
              %{
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
              |> Map.merge(uplink_metadata)
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

  # Marked not booked by an operator (#53): a later confirmation raises a conflict
  # (BookingResolutions) instead of silently scheduling the pass.
  defp apply_contact_side_effect(%ProviderReservation{
         lifecycle_state: state,
         metadata: %{"operator_resolution" => %{"action" => "not_booked"}}
       })
       when state in @materialized_states,
       do: :ok

  defp apply_contact_side_effect(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in @materialized_states do
    # Unpublished: every poll of a booked pass re-ensures its scheduled contact (a no-op after the
    # first), and the poll announces once if anything visible changed (ReservationChange).
    case materialize_scheduled_contact_unpublished(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_reservation_id
         ) do
      {:ok, _result} -> BookingOutcomes.booking_settled(reservation)
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_contact_side_effect(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in [:canceled, :failed] do
    with :ok <- cancel_scheduled_contact(reservation, state),
         :ok <- BookingOutcomes.booking_lost(reservation) do
      BookingOutcomes.booking_settled(reservation)
    end
  end

  defp apply_contact_side_effect(%ProviderReservation{lifecycle_state: :rejected} = reservation) do
    # An attested booking the provider rejects is lost like a canceled one (#53).
    if attested?(reservation) do
      with :ok <- cancel_scheduled_contact(reservation, :rejected),
           :ok <- BookingOutcomes.booking_lost(reservation) do
        BookingOutcomes.booking_settled(reservation)
      end
    else
      BookingOutcomes.booking_settled(reservation)
    end
  end

  defp apply_contact_side_effect(_reservation), do: :ok

  defp cancel_scheduled_contact(reservation, state) do
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

  defp delivery_descriptor(%{"delivery_descriptor" => descriptor} = response, reservation)
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
         :ok <- validate_descriptor_binding(descriptor, transport, reservation, response),
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

  defp validate_descriptor_binding(descriptor, transport, reservation, response) do
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
      activation_covers?(activation_window, pass_window(response, reservation))
    ]

    if Enum.all?(checks),
      do: :ok,
      else: {:error, :delivery_descriptor_conflicts_with_transport}
  end

  # The delivery covers the pass the same answer describes (a provider that moves a pass moves its
  # delivery with it), not the window Cadence holds from before that answer.
  defp pass_window(response, reservation) do
    with {:ok, starts_at, _offset} <- DateTime.from_iso8601(response["starts_at"] || ""),
         {:ok, ends_at, _offset} <- DateTime.from_iso8601(response["ends_at"] || "") do
      %{starts_at: starts_at, ends_at: ends_at}
    else
      _no_window -> %{starts_at: reservation.starts_at, ends_at: reservation.ends_at}
    end
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

  # The activation window is the pass's timing, so it moves with the pass; the rest is fixed.
  defp validate_immutable_descriptor(document, %{delivery_descriptor_document: existing}) do
    if Map.drop(document, ["activation_window"]) == Map.drop(existing, ["activation_window"]),
      do: :ok,
      else: {:error, :delivery_descriptor_changed}
  end

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
