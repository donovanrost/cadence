defmodule Cadence.GroundNetworks.ProviderEventInbox do
  @moduledoc "Durable, idempotent provider event delivery and processing queue."

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias Ecto.{Changeset, Multi}

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.GroundNetworks.{
    ProviderAudit,
    ProviderAuditEntry,
    ProviderEvent,
    ProviderEventCursor,
    ProviderEventCursors,
    ProviderEventInboxEntry,
    ProviderEvidenceStore,
    Validation
  }

  alias Cadence.GroundNetworks.ProviderEventInbox.InboxRow, as: ProviderEventInboxRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @known_event_types MapSet.new([
                       "run.created",
                       "run.paused",
                       "run.resumed",
                       "run.stopped",
                       "contact.modified",
                       "contact.pass_phase_changed",
                       "contact.result_updated",
                       "contact.status_changed",
                       "delivery.status_changed"
                     ])
  @payload_byte_limit 262_144
  @default_claim_limit 50
  @default_processing_timeout_ms 60_000

  @type ingest_summary :: %{
          inserted: non_neg_integer(),
          duplicates: non_neg_integer(),
          collisions: non_neg_integer(),
          quarantined: non_neg_integer(),
          entries: [ProviderEventInboxEntry.t()]
        }

  @spec ingest_page(ProviderEventCursor.t(), list(), term(), binary(), keyword()) ::
          {:ok, ingest_summary()} | {:error, term()}
  def ingest_page(
        %ProviderEventCursor{} = cursor,
        deliveries,
        next_cursor,
        lease_owner,
        opts \\ []
      )
      when is_list(deliveries) and is_binary(lease_owner) do
    with {:ok, prepared} <- prepare_deliveries(cursor, deliveries, opts) do
      recorded_at = now(opts)

      Multi.new()
      |> put_deliveries(prepared)
      |> maybe_fail_before_cursor(opts)
      |> ProviderEventCursors.put_advance(
        :cursor,
        cursor,
        lease_owner,
        next_cursor,
        %{
          last_fetched_at: recorded_at,
          last_event_at: latest_event_time(prepared, cursor.last_event_at)
        }
      )
      |> ProviderAudit.put_entry(:audit_entry, page_audit(cursor, prepared, recorded_at))
      |> Repo.transaction()
      |> unwrap_ingest(prepared)
    end
  end

  @doc "Common authenticated webhook persistence boundary; it does not expose a route."
  @spec ingest_delivery(map(), binary(), binary(), list(), keyword()) ::
          {:ok, ingest_summary()} | {:error, term()}
  def ingest_delivery(account_binding, environment_ref, channel_ref, deliveries, opts \\ [])
      when is_map(account_binding) and is_list(deliveries) do
    scope = %{
      organization_id: value(account_binding, :organization_id),
      provider_account_id: value(account_binding, :provider_account_id),
      provider_account_version: value(account_binding, :version),
      environment_ref: environment_ref,
      channel_ref: channel_ref,
      provider_event_cursor_id: nil
    }

    with {:ok, prepared} <- prepare_deliveries(scope, deliveries, opts) do
      recorded_at = now(opts)

      Multi.new()
      |> put_deliveries(prepared)
      |> ProviderAudit.put_entry(:audit_entry, delivery_audit(scope, prepared, recorded_at))
      |> Repo.transaction()
      |> unwrap_ingest(prepared)
    end
  end

  @spec fetch(binary(), binary()) :: {:ok, ProviderEventInboxEntry.t()} | {:error, :not_found}
  def fetch(organization_id, provider_event_inbox_id) do
    ProviderEventInboxRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_event_inbox_id == ^provider_event_inbox_id
    )
    |> Repo.one()
    |> row_result()
  end

  @spec list(binary(), keyword()) :: [ProviderEventInboxEntry.t()]
  def list(organization_id, opts \\ []) do
    ProviderEventInboxRow
    |> where([row], row.organization_id == ^organization_id)
    |> maybe_filter(:provider_account_id, Keyword.get(opts, :provider_account_id))
    |> maybe_filter(:processing_state, stringify(Keyword.get(opts, :processing_state)))
    |> order_by([row], desc: row.received_at, desc: row.provider_event_inbox_id)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
    |> Enum.map(&ProviderEventInboxRow.to_domain/1)
  end

  @spec counts(binary(), binary()) :: map()
  def counts(organization_id, provider_account_id) do
    ProviderEventInboxRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.provider_account_id == ^provider_account_id
    )
    |> group_by([row], row.processing_state)
    |> select([row], {row.processing_state, count(row.provider_event_inbox_id)})
    |> Repo.all()
    |> Map.new()
  end

  @spec claim(binary(), keyword()) :: {:ok, [ProviderEventInboxEntry.t()]}
  def claim(worker_ref, opts \\ []) when is_binary(worker_ref) do
    claimed_at = now(opts)

    stale_before =
      DateTime.add(
        claimed_at,
        -Keyword.get(opts, :processing_timeout_ms, @default_processing_timeout_ms),
        :millisecond
      )

    limit = Keyword.get(opts, :limit, @default_claim_limit)

    Repo.transaction(fn ->
      rows =
        ProviderEventInboxRow
        |> where(
          [row],
          row.processing_state in ["received", "reprocessing"] or
            (row.processing_state == "processing" and row.last_attempted_at <= ^stale_before)
        )
        |> order_by([row], asc: row.received_at, asc: row.provider_event_inbox_id)
        |> limit(^limit)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> Repo.all()

      Enum.map(rows, fn row ->
        row
        |> ProviderEventInboxRow.processing_changeset(%{
          processing_state: "processing",
          attempt_count: row.attempt_count + 1,
          last_attempted_at: claimed_at,
          error_document: %{"worker_ref" => worker_ref}
        })
        |> Repo.update!()
        |> ProviderEventInboxRow.to_domain()
      end)
    end)
    |> case do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec complete(ProviderEventInboxEntry.t(), map(), keyword()) ::
          {:ok, ProviderEventInboxEntry.t()} | {:error, term()}
  def complete(%ProviderEventInboxEntry{} = entry, resolution, opts \\ [])
      when is_map(resolution) do
    transition_with_audit(entry, :processed, resolution, %{}, "provider_event.processed", opts)
  end

  @spec retry(ProviderEventInboxEntry.t(), term(), keyword()) ::
          {:ok, ProviderEventInboxEntry.t()} | {:error, term()}
  def retry(%ProviderEventInboxEntry{} = entry, reason, opts \\ []) do
    error = bounded_error("processing_retry", reason, now(opts))

    transition_with_audit(
      entry,
      :received,
      %{},
      error,
      "provider_event.processing_retry_scheduled",
      opts
    )
  end

  @spec quarantine(ProviderEventInboxEntry.t(), term(), keyword()) ::
          {:ok, ProviderEventInboxEntry.t()} | {:error, term()}
  def quarantine(%ProviderEventInboxEntry{} = entry, reason, opts \\ []) do
    error = bounded_error("processing_quarantined", reason, now(opts))

    transition_with_audit(
      entry,
      :quarantined,
      %{},
      error,
      "provider_event.quarantined",
      opts
    )
  end

  @spec reprocess(Scope.t(), binary(), keyword()) ::
          {:ok, ProviderEventInboxEntry.t()} | {:error, term()}
  def reprocess(%Scope{} = current_scope, provider_event_inbox_id, opts \\ []) do
    with :ok <-
           Policy.authorize(current_scope, :manage_provider_accounts, %{
             organization_id: current_scope.organization_id
           }),
         {:ok, entry} <- fetch(current_scope.organization_id, provider_event_inbox_id),
         :ok <- ensure_quarantined(entry) do
      transition_with_audit(
        entry,
        :reprocessing,
        %{},
        %{},
        "provider_event.reprocessing_requested",
        Keyword.put_new(opts, :actor, actor_document(current_scope))
      )
    end
  end

  defp prepare_deliveries(scope, deliveries, opts) do
    deliveries
    |> Enum.reduce_while({:ok, []}, fn delivery, {:ok, prepared} ->
      case prepare_delivery(scope, delivery, opts) do
        {:ok, candidate} -> {:cont, {:ok, [candidate | prepared]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp prepare_delivery(scope, delivery, opts) do
    sanitized = delivery |> external_document() |> Validation.sanitize()
    canonical = ProviderEvidenceStore.canonical_document(sanitized)
    content_sha256 = sha256(canonical)
    payload_document = bounded_payload(sanitized, canonical, content_sha256)
    received_at = now(opts)

    with {:ok, evidence} <-
           ProviderEvidenceStore.persist(
             value(scope, :organization_id),
             value(scope, :provider_account_id),
             %{
               schema_type: "provider-event/v1",
               captured_at: received_at,
               document: payload_document,
               metadata: %{"channel_ref" => value(scope, :channel_ref)}
             }
           ) do
      {normalized, state, error_document} = normalize_delivery(sanitized, received_at)

      {:ok,
       %{
         scope: scope,
         normalized: normalized,
         payload_document: payload_document,
         content_sha256: content_sha256,
         provider_evidence_id: evidence.provider_evidence_id,
         received_at: received_at,
         processing_state: state,
         error_document: error_document
       }}
    end
  end

  defp normalize_delivery(sanitized, received_at) do
    case ProviderEvent.from_external(sanitized) do
      {:ok, %ProviderEvent{type: type} = event} ->
        if MapSet.member?(@known_event_types, type) do
          {event, :received, %{}}
        else
          {event, :quarantined,
           bounded_error("unknown_event_type", %{"event_type" => type}, received_at)}
        end

      {:error, reason} ->
        {nil, :quarantined, bounded_error("malformed_provider_event", reason, received_at)}
    end
  end

  defp put_deliveries(multi, prepared) do
    prepared
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {candidate, index}, current ->
      Multi.run(current, {:inbox, index}, fn repo, _changes ->
        insert_or_classify(repo, candidate)
      end)
    end)
  end

  defp insert_or_classify(repo, candidate) do
    lock_identity(repo, candidate)
    identity_rows = repo.all(identity_query(candidate))

    case Enum.find(identity_rows, &(&1.content_sha256 == candidate.content_sha256)) do
      %ProviderEventInboxRow{} = existing ->
        {:ok, {:duplicate, ProviderEventInboxRow.to_domain(existing)}}

      nil ->
        collision? = identity_rows != []
        entry = candidate_entry(candidate, collision?, identity_rows)

        case repo.insert(ProviderEventInboxRow.changeset(entry)) do
          {:ok, row} -> {:ok, {insert_outcome(entry), ProviderEventInboxRow.to_domain(row)}}
          {:error, %Changeset{} = changeset} -> resolve_insert_race(repo, candidate, changeset)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp lock_identity(repo, candidate) do
    identity =
      candidate
      |> identity_components()
      |> Enum.map_join("|", fn component ->
        encoded = to_string(component)
        "#{byte_size(encoded)}:#{encoded}"
      end)

    SQL.query!(repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [identity])
  end

  defp identity_components(candidate) do
    [
      value(candidate.scope, :organization_id),
      value(candidate.scope, :provider_account_id),
      value(candidate.scope, :provider_account_version),
      value(candidate.scope, :environment_ref),
      value(candidate.scope, :channel_ref),
      provider_event_id(candidate)
    ]
  end

  defp candidate_entry(candidate, collision?, identity_rows) do
    normalized = candidate.normalized
    payload = candidate.payload_document

    collision_error =
      if collision? do
        bounded_error(
          "provider_event_identity_collision",
          %{"existing_hashes" => Enum.map(identity_rows, & &1.content_sha256)},
          candidate.received_at
        )
      else
        candidate.error_document
      end

    ProviderEventInboxEntry.new(%{
      provider_event_inbox_id: Cadence.Ids.new("provider_event_inbox"),
      organization_id: value(candidate.scope, :organization_id),
      provider_account_id: value(candidate.scope, :provider_account_id),
      provider_account_version: value(candidate.scope, :provider_account_version),
      provider_event_cursor_id: value(candidate.scope, :provider_event_cursor_id),
      environment_ref: value(candidate.scope, :environment_ref),
      channel_ref: value(candidate.scope, :channel_ref),
      provider_event_id: event_value(normalized, payload, :id, collision_event_id(candidate)),
      schema_version: event_value(normalized, payload, :schema_version),
      event_type: event_value(normalized, payload, :type),
      sequence: event_value(normalized, payload, :sequence),
      resource_type: event_value(normalized, payload, :resource_type),
      resource_id: event_value(normalized, payload, :resource_id),
      resource_revision: event_value(normalized, payload, :resource_revision),
      request_id: event_value(normalized, payload, :request_id),
      correlation_id: event_value(normalized, payload, :correlation_id),
      client_reference: event_value(normalized, payload, :client_reference),
      provider_occurred_at: event_datetime(normalized, payload),
      received_at: candidate.received_at,
      payload_document: payload,
      content_sha256: candidate.content_sha256,
      provider_evidence_id: candidate.provider_evidence_id,
      processing_state: if(collision?, do: :quarantined, else: candidate.processing_state),
      error_document: collision_error,
      identity_collision: collision?
    })
  end

  defp identity_query(candidate) do
    provider_event_id = provider_event_id(candidate)

    from(row in ProviderEventInboxRow,
      where:
        row.organization_id == ^value(candidate.scope, :organization_id) and
          row.provider_account_id == ^value(candidate.scope, :provider_account_id) and
          row.provider_account_version == ^value(candidate.scope, :provider_account_version) and
          row.environment_ref == ^value(candidate.scope, :environment_ref) and
          row.channel_ref == ^value(candidate.scope, :channel_ref) and
          row.provider_event_id == ^provider_event_id,
      lock: "FOR UPDATE"
    )
  end

  defp provider_event_id(candidate) do
    event_value(
      candidate.normalized,
      candidate.payload_document,
      :id,
      collision_event_id(candidate)
    )
  end

  defp resolve_insert_race(repo, candidate, changeset) do
    case repo.one(
           from(row in identity_query(candidate),
             where: row.content_sha256 == ^candidate.content_sha256
           )
         ) do
      nil -> {:error, changeset}
      row -> {:ok, {:duplicate, ProviderEventInboxRow.to_domain(row)}}
    end
  end

  defp maybe_fail_before_cursor(multi, opts) do
    if Keyword.get(opts, :fail_before_cursor_commit?, false) do
      Multi.run(multi, :injected_failure, fn _repo, _changes ->
        {:error, :injected_before_cursor_commit}
      end)
    else
      multi
    end
  end

  defp unwrap_ingest({:ok, changes}, _prepared) do
    outcomes =
      changes
      |> Enum.filter(fn {key, _value} -> match?({:inbox, _index}, key) end)
      |> Enum.map(fn {_key, outcome} -> outcome end)

    {:ok, summarize(outcomes)}
  end

  defp unwrap_ingest({:error, operation, reason, _changes}, _prepared),
    do: {:error, {operation, reason}}

  defp summarize(outcomes) do
    Enum.reduce(
      outcomes,
      %{inserted: 0, duplicates: 0, collisions: 0, quarantined: 0, entries: []},
      fn {outcome, entry}, summary ->
        summary
        |> Map.update!(:entries, &[entry | &1])
        |> increment_outcome(outcome)
        |> maybe_increment_quarantine(entry)
      end
    )
    |> Map.update!(:entries, &Enum.reverse/1)
  end

  defp increment_outcome(summary, :duplicate), do: Map.update!(summary, :duplicates, &(&1 + 1))
  defp increment_outcome(summary, :collision), do: Map.update!(summary, :collisions, &(&1 + 1))
  defp increment_outcome(summary, :inserted), do: Map.update!(summary, :inserted, &(&1 + 1))

  defp maybe_increment_quarantine(summary, %{processing_state: :quarantined}),
    do: Map.update!(summary, :quarantined, &(&1 + 1))

  defp maybe_increment_quarantine(summary, _entry), do: summary

  defp insert_outcome(%{identity_collision: true}), do: :collision
  defp insert_outcome(_entry), do: :inserted

  defp transition_with_audit(entry, state, resolution, error, action, opts) do
    transition(entry, state, resolution, error, action, opts)
  end

  defp transition(entry, state, resolution, error, action, opts) do
    processed_at = if(state == :processed, do: now(opts))

    attrs =
      resolution
      |> Map.take([
        :mission_id,
        :provider_id,
        :provider_reservation_id,
        :scheduled_contact_id,
        :contact_id
      ])
      |> Map.merge(%{
        processing_state: Atom.to_string(state),
        processed_at: processed_at,
        error_document: error
      })

    multi =
      Multi.new()
      |> Multi.run(:inbox_entry, fn repo, _changes -> update_processing(repo, entry, attrs) end)

    audit_entry = apply_resolution(entry, resolution)

    multi =
      if action do
        ProviderAudit.put_entry(
          multi,
          :audit_entry,
          processing_audit(audit_entry, action, state, opts)
        )
      else
        multi
      end

    case Repo.transaction(multi) do
      {:ok, %{inbox_entry: updated}} -> {:ok, updated}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  defp update_processing(repo, entry, attrs) do
    case repo.get(ProviderEventInboxRow, entry.provider_event_inbox_id) do
      nil ->
        {:error, :provider_event_inbox_not_found}

      row ->
        row
        |> ProviderEventInboxRow.processing_changeset(attrs)
        |> repo.update()
        |> domain_result()
    end
  end

  defp domain_result({:ok, row}), do: {:ok, ProviderEventInboxRow.to_domain(row)}
  defp domain_result({:error, reason}), do: {:error, reason}

  defp apply_resolution(entry, resolution) do
    Enum.reduce(
      [:mission_id, :provider_id, :provider_reservation_id, :scheduled_contact_id, :contact_id],
      entry,
      fn field, current ->
        case Map.fetch(resolution, field) do
          {:ok, value} -> Map.put(current, field, value)
          :error -> current
        end
      end
    )
  end

  defp page_audit(cursor, prepared, recorded_at) do
    ProviderAuditEntry.new(%{
      organization_id: cursor.organization_id,
      provider_account_id: cursor.provider_account_id,
      action: "provider_event.page_ingested",
      outcome: "succeeded",
      recorded_at: recorded_at,
      source_document: %{
        "kind" => "poller",
        "environment_ref" => cursor.environment_ref,
        "channel_ref" => cursor.channel_ref,
        "stream_ref" => cursor.stream_ref
      },
      actor_document: %{"kind" => "system", "id" => "provider_event_poller"},
      current_document: %{"delivery_count" => length(prepared)}
    })
  end

  defp delivery_audit(scope, prepared, recorded_at) do
    ProviderAuditEntry.new(%{
      organization_id: value(scope, :organization_id),
      provider_account_id: value(scope, :provider_account_id),
      action: "provider_event.delivery_ingested",
      outcome: "succeeded",
      recorded_at: recorded_at,
      source_document: %{
        "kind" => "webhook",
        "environment_ref" => value(scope, :environment_ref),
        "channel_ref" => value(scope, :channel_ref)
      },
      actor_document: %{"kind" => "provider"},
      current_document: %{"delivery_count" => length(prepared)}
    })
  end

  defp processing_audit(entry, action, state, opts) do
    ProviderAuditEntry.new(%{
      organization_id: entry.organization_id,
      mission_id: entry.mission_id,
      provider_account_id: entry.provider_account_id,
      provider_id: entry.provider_id,
      provider_reservation_id: entry.provider_reservation_id,
      scheduled_contact_id: entry.scheduled_contact_id,
      contact_id: entry.contact_id,
      provider_event_id: entry.provider_event_id,
      action: action,
      outcome: Atom.to_string(state),
      provider_occurred_at: entry.provider_occurred_at,
      recorded_at: now(opts),
      correlation_id: entry.correlation_id,
      request_id: entry.request_id,
      client_reference: entry.client_reference,
      source_document: %{"kind" => "provider_event_inbox"},
      actor_document: Keyword.get(opts, :actor, %{"kind" => "system"})
    })
  end

  defp latest_event_time(prepared, fallback) do
    prepared
    |> Enum.map(& &1.normalized)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.occurred_at)
    |> Enum.reduce(fallback, fn occurred_at, latest ->
      if is_nil(latest) or DateTime.compare(occurred_at, latest) == :gt,
        do: occurred_at,
        else: latest
    end)
  end

  defp bounded_payload(sanitized, canonical, content_sha256) do
    if byte_size(canonical) <= @payload_byte_limit do
      sanitized
    else
      %{
        "payload_omitted" => true,
        "original_byte_count" => byte_size(canonical),
        "original_content_sha256" => content_sha256,
        "provider_event_id" => string_value(sanitized, "id")
      }
    end
  end

  defp bounded_error(category, reason, recorded_at) do
    %{
      "category" => category,
      "reason" => sanitize_reason(reason),
      "recorded_at" => DateTime.to_iso8601(recorded_at)
    }
  end

  defp event_value(event, payload, field, default \\ nil)

  defp event_value(%ProviderEvent{} = event, _payload, field, _default),
    do: Map.fetch!(event, field)

  defp event_value(nil, payload, field, default),
    do: Map.get(payload, Atom.to_string(field), default)

  defp event_datetime(%ProviderEvent{} = event, _payload), do: event.occurred_at

  defp event_datetime(nil, payload) do
    case string_value(payload, "occurred_at") do
      nil ->
        nil

      value ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _other -> nil
        end
    end
  end

  defp collision_event_id(candidate),
    do: "invalid:" <> String.slice(candidate.content_sha256, 0, 32)

  defp external_document(%ProviderEvent{evidence: evidence}), do: evidence
  defp external_document(document) when is_map(document), do: document
  defp external_document(value), do: %{"invalid_delivery" => JsonDocument.encode(value)}

  defp string_value(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp ensure_quarantined(%{processing_state: :quarantined}), do: :ok
  defp ensure_quarantined(_entry), do: {:error, :provider_event_not_quarantined}

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp row_result(nil), do: {:error, :not_found}
  defp row_result(row), do: {:ok, ProviderEventInboxRow.to_domain(row)}

  defp sanitize_reason(reason) do
    case JsonDocument.encode(reason) do
      document when is_map(document) -> Validation.sanitize(document)
      value -> value
    end
  end

  defp sha256(bytes),
    do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp actor_document(scope) do
    %{
      "kind" => "user",
      "id" => scope.user && scope.user.user_id,
      "role" => scope.role && Atom.to_string(scope.role)
    }
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
