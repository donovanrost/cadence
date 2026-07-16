defmodule Cadence.GroundNetworks.ProviderAudit do
  @moduledoc "Append-only provider audit ledger and rebuildable operational projection."

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.GroundNetworks.ProviderAuditEntry
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.Schemas.ProviderAuditEntryRow
  alias Cadence.Repo

  @spec append(ProviderAuditEntry.t()) :: {:ok, ProviderAuditEntry.t()} | {:error, term()}
  def append(%ProviderAuditEntry{} = entry) do
    entry
    |> ProviderAuditEntryRow.changeset()
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, ProviderAuditEntryRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec append_and_project(ProviderAuditEntry.t()) ::
          {:ok, ProviderAuditEntry.t()} | {:error, term()}
  def append_and_project(%ProviderAuditEntry{} = entry) do
    with {:ok, persisted} <- append(entry),
         {:ok, _projection} <- project_entry(persisted) do
      {:ok, persisted}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Adds an audit insert to a caller-owned transaction."
  @spec put_entry(Multi.t(), Multi.name(), ProviderAuditEntry.t()) :: Multi.t()
  def put_entry(%Multi{} = multi, name, %ProviderAuditEntry{} = entry) do
    Multi.insert(multi, name, ProviderAuditEntryRow.changeset(entry))
  end

  @spec fetch_entry(binary(), binary()) :: {:ok, ProviderAuditEntry.t()} | {:error, :not_found}
  def fetch_entry(organization_id, provider_audit_entry_id)
      when is_binary(organization_id) and is_binary(provider_audit_entry_id) do
    ProviderAuditEntryRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_audit_entry_id == ^provider_audit_entry_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, ProviderAuditEntryRow.to_domain(row)}
    end
  end

  @spec list_entries(binary(), keyword()) :: [ProviderAuditEntry.t()]
  def list_entries(organization_id, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    ProviderAuditEntryRow
    |> where([row], row.organization_id == ^organization_id)
    |> maybe_filter(:mission_id, Keyword.get(opts, :mission_id))
    |> maybe_filter(:provider_account_id, Keyword.get(opts, :provider_account_id))
    |> maybe_filter(:provider_reservation_id, Keyword.get(opts, :provider_reservation_id))
    |> maybe_filter(:provider_change_id, Keyword.get(opts, :provider_change_id))
    |> maybe_filter(:correlation_id, Keyword.get(opts, :correlation_id))
    |> order_by([row], desc: row.recorded_at, desc: row.provider_audit_entry_id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ProviderAuditEntryRow.to_domain/1)
  end

  @spec project_entry(ProviderAuditEntry.t()) ::
          {:ok, Event.t() | :organization_only} | {:error, term()}
  def project_entry(%ProviderAuditEntry{mission_id: nil}), do: {:ok, :organization_only}

  def project_entry(%ProviderAuditEntry{} = entry) do
    entry
    |> operational_event()
    |> OperationalEvents.persist_event()
  end

  @spec operational_event(ProviderAuditEntry.t()) :: Event.t()
  def operational_event(%ProviderAuditEntry{mission_id: mission_id} = entry)
      when is_binary(mission_id) do
    Event.new(%{
      event_id: projection_event_id(entry.provider_audit_entry_id),
      organization_id: entry.organization_id,
      mission_id: mission_id,
      occurred_at: entry.provider_occurred_at || entry.recorded_at,
      recorded_at: entry.recorded_at,
      effective_at: entry.effective_at,
      category: :contact,
      kind: :provider_audit_recorded,
      severity: projection_severity(entry.outcome),
      actor: projection_actor(entry.actor_document),
      subject: projection_subject(entry),
      scope: reference_document(entry),
      causality: projection_causality(entry),
      payload: projection_payload(entry),
      previous: entry.previous_document,
      current: entry.current_document,
      metadata: %{
        "provider_audit_entry_id" => entry.provider_audit_entry_id,
        "source" => entry.source_document,
        "metadata" => entry.metadata
      }
    })
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp projection_event_id(entry_id),
    do: "operational_event:provider_audit_entry:#{entry_id}"

  defp projection_causality(entry) do
    %{
      correlation_id: entry.correlation_id,
      causation_event_id: maybe_projection_event_id(entry.causation_entry_id),
      source_record_kind: :provider_audit_entry,
      source_record_id: entry.provider_audit_entry_id
    }
    |> compact()
  end

  defp projection_payload(entry) do
    reference_document(entry)
    |> Map.merge(%{
      "action" => entry.action,
      "outcome" => entry.outcome,
      "request_id" => entry.request_id,
      "client_reference" => entry.client_reference,
      "provider_event_id" => entry.provider_event_id,
      "causation_entry_id" => entry.causation_entry_id,
      "supersedes_entry_id" => entry.supersedes_entry_id,
      "credential_ref" => entry.credential_ref,
      "credential_registry_version" => entry.credential_registry_version,
      "credential_backend_version" => entry.credential_backend_version,
      "decision" => entry.decision_document,
      "policy" => entry.policy_document,
      "evidence_references" => entry.evidence_references
    })
    |> compact()
  end

  defp reference_document(entry) do
    references = entry.references

    %{
      "provider_account_id" => references.provider_account_id,
      "provider_account_grant_id" => references.provider_account_grant_id,
      "provider_id" => references.provider_id,
      "provider_reservation_id" => references.provider_reservation_id,
      "provider_change_id" => references.provider_change_id,
      "contact_id" => references.contact_id,
      "scheduled_contact_id" => references.scheduled_contact_id
    }
    |> compact()
  end

  defp projection_subject(entry) do
    references = entry.references

    case references.contact_id || references.scheduled_contact_id ||
           references.provider_reservation_id do
      nil -> nil
      contact_id -> %{kind: :contact, id: contact_id}
    end
  end

  defp projection_actor(actor) do
    kind = Map.get(actor, "kind", Map.get(actor, :kind, "system"))

    actor
    |> Map.put("kind", projection_actor_kind(kind))
    |> Map.delete(:kind)
  end

  defp projection_actor_kind("user"), do: :user
  defp projection_actor_kind(:user), do: :user
  defp projection_actor_kind("service"), do: :service
  defp projection_actor_kind(:service), do: :service
  defp projection_actor_kind("provider"), do: :service
  defp projection_actor_kind(:provider), do: :service
  defp projection_actor_kind("replay"), do: :replay
  defp projection_actor_kind(:replay), do: :replay
  defp projection_actor_kind(_kind), do: :system

  defp projection_severity(outcome) when outcome in ["failed", "rejected", "blocked"],
    do: :error

  defp projection_severity(outcome)
       when outcome in ["warning", "approval_pending", "acknowledgment_required"],
       do: :warning

  defp projection_severity(_outcome), do: :info

  defp maybe_projection_event_id(nil), do: nil
  defp maybe_projection_event_id(entry_id), do: projection_event_id(entry_id)

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}, []] end)
    |> Map.new()
  end
end
