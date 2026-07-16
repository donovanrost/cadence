defmodule Cadence.Persistence.Schemas.ProviderEventCursorRow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.GroundNetworks.ProviderEventCursor
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:provider_event_cursor_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "provider_event_cursors" do
    field(:organization_id, :string)
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:environment_ref, :string)
    field(:channel_ref, :string)
    field(:stream_ref, :string)
    field(:cursor_document, :map, default: %{"value" => nil})
    field(:health, :string)
    field(:last_fetched_at, :utc_datetime_usec)
    field(:last_advanced_at, :utc_datetime_usec)
    field(:last_event_at, :utc_datetime_usec)
    field(:lease_owner, :string)
    field(:lease_expires_at, :utc_datetime_usec)
    field(:consecutive_failures, :integer, default: 0)
    field(:error_document, :map, default: %{})
    timestamps()
  end

  @identity_fields [
    :provider_event_cursor_id,
    :organization_id,
    :provider_account_id,
    :provider_account_version,
    :environment_ref,
    :channel_ref,
    :stream_ref
  ]

  @operational_fields [
    :cursor_document,
    :health,
    :last_fetched_at,
    :last_advanced_at,
    :last_event_at,
    :lease_owner,
    :lease_expires_at,
    :consecutive_failures,
    :error_document
  ]

  @spec changeset(ProviderEventCursor.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderEventCursor{} = cursor) do
    %__MODULE__{}
    |> cast(domain_attrs(cursor), @identity_fields ++ @operational_fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@identity_fields ++ [:cursor_document, :health, :error_document])
    |> validate_number(:provider_account_version, greater_than: 0)
    |> validate_number(:consecutive_failures, greater_than_or_equal_to: 0)
    |> validate_inclusion(:health, ["healthy", "degraded", "disabled", "unknown"])
    |> unique_constraint(@identity_fields -- [:provider_event_cursor_id],
      name: :provider_event_cursors_stream_idx
    )
  end

  @spec operational_changeset(struct(), map()) :: Ecto.Changeset.t()
  def operational_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> maybe_wrap_cursor()
      |> maybe_stringify_health()
      |> maybe_wrap_error()

    row
    |> cast(attrs, @operational_fields)
    |> validate_required([:cursor_document, :health, :error_document])
    |> validate_number(:consecutive_failures, greater_than_or_equal_to: 0)
    |> validate_inclusion(:health, ["healthy", "degraded", "disabled", "unknown"])
  end

  @spec to_domain(struct()) :: ProviderEventCursor.t()
  def to_domain(%__MODULE__{} = row) do
    ProviderEventCursor.new(%{
      provider_event_cursor_id: row.provider_event_cursor_id,
      organization_id: row.organization_id,
      provider_account_id: row.provider_account_id,
      provider_account_version: row.provider_account_version,
      environment_ref: row.environment_ref,
      channel_ref: row.channel_ref,
      stream_ref: row.stream_ref,
      cursor: JsonDocument.unwrap_value(row.cursor_document),
      health: row.health,
      last_fetched_at: row.last_fetched_at,
      last_advanced_at: row.last_advanced_at,
      last_event_at: row.last_event_at,
      lease_owner: row.lease_owner,
      lease_expires_at: row.lease_expires_at,
      consecutive_failures: row.consecutive_failures,
      error_document: JsonDocument.unwrap_value(row.error_document)
    })
  end

  defp domain_attrs(cursor) do
    cursor
    |> Map.from_struct()
    |> Map.put(:cursor_document, JsonDocument.wrap_value(cursor.cursor))
    |> Map.put(:health, Atom.to_string(cursor.health))
    |> Map.put(:error_document, JsonDocument.wrap_value(cursor.error_document))
  end

  defp maybe_wrap_cursor(attrs) do
    case Map.fetch(attrs, :cursor) do
      {:ok, cursor} ->
        attrs |> Map.delete(:cursor) |> Map.put(:cursor_document, JsonDocument.wrap_value(cursor))

      :error ->
        attrs
    end
  end

  defp maybe_stringify_health(%{health: health} = attrs) when is_atom(health),
    do: %{attrs | health: Atom.to_string(health)}

  defp maybe_stringify_health(attrs), do: attrs

  defp maybe_wrap_error(attrs) do
    case Map.fetch(attrs, :error_document) do
      {:ok, error_document} ->
        Map.put(attrs, :error_document, JsonDocument.wrap_value(error_document))

      :error ->
        attrs
    end
  end
end
