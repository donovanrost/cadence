defmodule Cadence.Platform.ScopedSettings do
  @moduledoc "Versioned storage for domain-owned organization defaults and mission overrides."
  import Ecto.Query
  alias Cadence.Ids
  alias Cadence.Platform.ContentHash
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Platform.ScopedSettings.RevisionRow
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  # The organization and its missions share a section lock. Approval admission
  # uses this same lock so a setting cannot change during its durable effect.
  def with_lock(organization_id, section_id, operation) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, organization_id, section_id}))

    case Repo.transaction(fn ->
           SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1::bigint)", [key])
           rollback_error(operation.())
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp rollback_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_error(result), do: result

  def load(organization_id, mission_id, section_id, default) do
    Map.fetch!(load_many(organization_id, [mission_id], section_id, default), mission_id)
  end

  def load_many(organization_id, mission_ids, section_id, default) do
    keys = Enum.uniq(["organization" | Enum.map(mission_ids, &scope_key/1)])

    # One statement captures both levels, including the absence of an override.
    rows =
      from(row in RevisionRow,
        where: row.organization_id == ^organization_id and row.section_id == ^section_id,
        where: row.scope_key in ^keys,
        distinct: row.scope_key,
        order_by: [asc: row.scope_key, desc: row.version]
      )
      |> Repo.all()
      |> Map.new(&{&1.scope_key, &1})

    Map.new(mission_ids, fn mission ->
      {mission, snapshot(rows, organization_id, mission, section_id, default)}
    end)
  end

  defp snapshot(rows, organization_id, mission_id, section_id, default) do
    scope_key = scope_key(mission_id)
    organization = rows["organization"]
    current = rows[scope_key]
    organization_document = if organization, do: organization.document, else: default
    organization_value = organization_document["value"]
    allow_override = organization_document["allow_override"]
    saved = if current, do: current.document["value"], else: nil
    source = source(mission_id, saved, allow_override)

    %{
      token:
        ContentHash.term_sha256(
          {1, organization_id, scope_key, section_id, organization && organization.revision_id,
           current && current.revision_id, default}
        ),
      version: if(current, do: current.version, else: 0),
      saved: if(is_nil(mission_id), do: organization_value, else: saved),
      effective: if(source == "overridden", do: saved, else: organization_value),
      organization_default: organization_value,
      allow_override: allow_override,
      source: source
    }
  end

  def save(organization_id, mission_id, section_id, default, expected_token, document, actor) do
    with_lock(organization_id, section_id, fn ->
      current = load(organization_id, mission_id, section_id, default)

      cond do
        not is_binary(expected_token) or current.token != expected_token ->
          {:error, :settings_changed}

        not is_nil(mission_id) and not current.allow_override ->
          {:error, :settings_enforced_by_organization}

        true ->
          Repo.insert(
            RevisionRow.changeset(%{
              revision_id: Ids.new("settings_revision"),
              organization_id: organization_id,
              scope_key: scope_key(mission_id),
              section_id: section_id,
              version: current.version + 1,
              document: document,
              actor_id: actor.id,
              actor_name: actor.name
            })
          )
      end
    end)
    |> ScopedReadUpdates.publish_result(:settings_changed, organization_id, mission_id)
  end

  def history(organization_id, mission_id, section_id) do
    key = scope_key(mission_id)

    from(row in RevisionRow,
      where: row.organization_id == ^organization_id and row.scope_key == ^key,
      where: row.section_id == ^section_id,
      order_by: [desc: row.version],
      limit: 10
    )
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.revision_id,
        version: &1.version,
        actor: &1.actor_name,
        saved_at: DateTime.to_iso8601(&1.inserted_at)
      }
    )
  end

  defp scope_key(nil), do: "organization"
  defp scope_key(mission_id), do: "mission:#{mission_id}"
  defp source(nil, _saved, _allowed), do: "organization"
  defp source(_mission, _saved, false), do: "enforced"
  defp source(_mission, nil, true), do: "inherited"
  defp source(_mission, _saved, true), do: "overridden"
end
