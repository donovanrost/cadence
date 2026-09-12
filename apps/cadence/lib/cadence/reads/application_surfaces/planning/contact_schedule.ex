defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactSchedule do
  @moduledoc "Scoped route readiness and paged ledgers for native contact scheduling."
  alias Cadence.Auth.Scope
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Control.Contacts
  alias Cadence.Reads.ApplicationSurfaces.Planning.ContactScheduleProjection
  alias Cadence.SpacecraftStore

  @pages ~w(spacecraft_page routes_page findings_page scheduled_page realized_page reservations_page)
  @keys ~w(spacecraft_id spacecraft_q) ++ @pages

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(params, fn {k, v} -> k in @keys and text?(v, 240) end),
         true <- is_nil(params["spacecraft_id"]) or identifier?(params["spacecraft_id"]),
         q = Map.get(params, "spacecraft_q", ""),
         true <- text?(q, 120),
         {:ok, pages} <- pages(params) do
      {:ok,
       Map.merge(pages, %{
         "spacecraft_id" => params["spacecraft_id"],
         "spacecraft_q" => String.trim(q)
       })}
    else
      _ -> {:error, :invalid_contact_schedule_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_contact_schedule_query}

  def load(%Scope{} = scope, mission, params) do
    org = scope.organization_id
    mid = mission.mission_id

    with {:ok, q} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, selected, ready} <- selection(org, mid, q["spacecraft_id"]),
         {:ok, scheduled} <-
           Contacts.list_contact_records_page(org, mid, :scheduled, q["scheduled_page"]),
         {:ok, realized} <-
           Contacts.list_contact_records_page(org, mid, :realized, q["realized_page"]),
         {:ok, reservations} <-
           Contacts.list_provider_reservations_page(org, mid, q["reservations_page"]) do
      spacecraft =
        SpacecraftStore.list_spacecraft_page(org, mid,
          page: q["spacecraft_page"],
          page_size: 25,
          search: q["spacecraft_q"]
        )

      {:ok,
       %{
         schedule:
           ContactScheduleProjection.project(scope, mid, q, %{
             spacecraft: spacecraft,
             selected: selected,
             ready: ready,
             scheduled: scheduled,
             realized: realized,
             reservations: reservations
           })
       }}
    end
  end

  defp selection(_, _, nil), do: {:ok, nil, %{routes: [], findings: []}}

  defp selection(org, mid, id) do
    with {:ok, craft} <- SpacecraftStore.fetch_spacecraft(org, mid, id),
         {:ok, ready} <- ProviderScheduling.list_ready_downlink_routes(org, mid, id),
         do: {:ok, craft, ready}
  end

  defp pages(params) do
    Enum.reduce_while(@pages, {:ok, %{}}, fn key, {:ok, acc} ->
      case page(Map.get(params, key, "1")) do
        {:ok, v} -> {:cont, {:ok, Map.put(acc, key, v)}}
        _ -> {:halt, {:error, :invalid_page}}
      end
    end)
  end

  defp page(v) do
    with true <- Regex.match?(~r/\A[1-9][0-9]{0,6}\z/, v),
         {n, ""} when n <= 1_000_000 <- Integer.parse(v),
         do: {:ok, n},
         else: (_ -> {:error, :invalid_page})
  end

  defp text?(v, max), do: is_binary(v) and byte_size(v) <= max and String.valid?(v)
  defp identifier?(v), do: text?(v, 240) and v != "" and not Regex.match?(~r/[\x00-\x20\x7f]/, v)
end
