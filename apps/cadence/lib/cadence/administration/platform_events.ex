defmodule Cadence.Administration.PlatformEvents do
  @moduledoc """
  The platform audit (console L7): what platform administrators did, with the actor from the
  scope, the organization it touched (if any) and a target. Entries hold ids, names and
  timestamps, never a token, password or digest.

  Actions: `organization_created`, `invitation_created`, `invitation_withdrawn`,
  `service_identity_issued`, `service_identity_rotated`, `service_identity_revoked`,
  `admin_mode_entered` (`details.expires_at`), `admin_mode_left`, `platform_binding_switched`
  (DECISIONS #90: `details` reason, affected_missions, live_passes_total, from and to).
  """

  import Ecto.Query

  require Logger

  alias Cadence.Administration.PlatformEventRow
  alias Cadence.Ids
  alias Cadence.Repo

  @actions ~w(organization_created invitation_created invitation_withdrawn service_identity_issued
              service_identity_rotated service_identity_revoked admin_mode_entered admin_mode_left
              platform_binding_switched)

  @doc "The actions the platform audit records."
  def actions, do: @actions

  @doc """
  Records one action. `attrs`: `organization_id`, `target` (`{kind, id, label}`), `details`.
  Never raises: an audit write failure is logged, not turned into a failed action.
  """
  @spec record(binary(), binary(), map()) :: :ok
  def record(actor_id, action, attrs \\ %{}) when action in @actions and is_binary(actor_id) do
    {kind, id, label} = Map.get(attrs, :target, {nil, nil, nil})

    Repo.insert!(%PlatformEventRow{
      platform_event_id: Ids.new("plev"),
      actor_id: actor_id,
      action: action,
      organization_id: Map.get(attrs, :organization_id),
      target_kind: kind,
      target_id: id,
      target_label: label,
      details: Map.get(attrs, :details, %{}),
      occurred_at: DateTime.utc_now()
    })

    :ok
  rescue
    error ->
      Logger.error("platform audit write failed (#{action}): #{Exception.message(error)}")
      :ok
  end

  @doc "Newest first; `after` is the last id of the previous page."
  @spec list(keyword()) :: [PlatformEventRow.t()]
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    PlatformEventRow
    |> maybe_organization(Keyword.get(opts, :organization_id))
    |> maybe_after(Keyword.get(opts, :after))
    |> order_by([e], desc: e.occurred_at, desc: e.platform_event_id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Who created each of these organizations, when recorded: `%{organization_id => actor_id}`."
  @spec creators([binary()]) :: %{binary() => binary()}
  def creators([]), do: %{}

  def creators(organization_ids) do
    PlatformEventRow
    |> where([e], e.action == "organization_created" and e.organization_id in ^organization_ids)
    |> select([e], {e.organization_id, e.actor_id})
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_organization(query, nil), do: query
  defp maybe_organization(query, id), do: where(query, [e], e.organization_id == ^id)

  defp maybe_after(query, nil), do: query

  defp maybe_after(query, after_id) do
    case Repo.get(PlatformEventRow, after_id) do
      nil ->
        query

      last ->
        where(
          query,
          [e],
          e.occurred_at < ^last.occurred_at or
            (e.occurred_at == ^last.occurred_at and e.platform_event_id < ^last.platform_event_id)
        )
    end
  end
end
