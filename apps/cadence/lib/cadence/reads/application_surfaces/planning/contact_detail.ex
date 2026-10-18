defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactDetail do
  @moduledoc "Scoped reservation review with independent immutable change and audit paging."
  alias Cadence.Auth.Scope
  alias Cadence.Control.Contacts
  alias Cadence.GroundNetworks.ProviderAudit
  alias Cadence.Reads.ApplicationSurfaces.Planning.ReservationProjection

  @keys ~w(provider_reservation_id change_id before_revision before_audit)
  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(params, fn {k, v} -> k in @keys and identifier?(v) end),
         true <- identifier?(params["provider_reservation_id"]),
         {:ok, before} <- revision(params["before_revision"]) do
      {:ok, Map.merge(Map.new(@keys, &{&1, nil}), Map.put(params, "before_revision", before))}
    else
      _ -> {:error, :invalid_reservation_review_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_reservation_review_query}

  def load(%Scope{} = scope, mission, params) do
    org = scope.organization_id
    mid = mission.mission_id

    with {:ok, q} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, reservation} <-
           Contacts.fetch_provider_reservation(org, mid, q["provider_reservation_id"]),
         {:ok, latest} <-
           Contacts.list_provider_changes_page(org, mid, reservation.provider_reservation_id, nil),
         {:ok, selected} <- selected(org, mid, reservation, q["change_id"], latest.entries),
         {:ok, changes} <- history(org, mid, reservation, q["before_revision"], latest),
         {:ok, audit} <-
           ProviderAudit.list_reservation_page(
             org,
             mid,
             reservation.provider_reservation_id,
             q["before_audit"]
           ) do
      q = Map.put(q, "change_id", selected && selected.provider_reservation_change_id)

      {:ok,
       %{detail: ReservationProjection.project(scope, reservation, selected, q, changes, audit)}}
    end
  end

  defp selected(_, _, _, nil, entries), do: {:ok, List.first(entries)}

  defp selected(org, mid, reservation, id, _) do
    with {:ok, change} <- Contacts.fetch_provider_change(org, id),
         true <-
           change.mission_id == mid and
             change.provider_reservation_id == reservation.provider_reservation_id do
      {:ok, change}
    else
      _ -> {:error, :reservation_change_not_found}
    end
  end

  defp history(_, _, _, nil, latest), do: {:ok, latest}

  defp history(org, mid, r, before, _),
    do: Contacts.list_provider_changes_page(org, mid, r.provider_reservation_id, before)

  defp revision(nil), do: {:ok, nil}

  defp revision(v) do
    with true <- Regex.match?(~r/\A[1-9][0-9]{0,9}\z/, v),
         {n, ""} when n <= 2_147_483_647 <- Integer.parse(v),
         do: {:ok, n},
         else: (_ -> {:error, :invalid_revision})
  end

  defp identifier?(v) when is_binary(v) and byte_size(v) in 1..240,
    do: String.valid?(v) and not Regex.match?(~r/[\x00-\x20\x7f]/, v)

  defp identifier?(_), do: false
end
