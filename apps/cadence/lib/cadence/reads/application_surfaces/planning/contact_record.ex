defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactRecord do
  @moduledoc "Scoped planned and realized contact records, with independently pinned schedule history."
  alias Cadence.Auth.Scope
  alias Cadence.Control.Contacts
  alias Cadence.Reads.ApplicationSurfaces.Planning.ContactRecordProjection
  @pages ~w(scheduled_paths_page realized_paths_page sources_page intents_page)
  @keys ~w(contact_id revision before_revision) ++ @pages

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(params, fn {k, v} -> k in @keys and identifier?(v) end),
         true <- identifier?(params["contact_id"]),
         {:ok, revision} <- number(params["revision"], 2_147_483_647),
         {:ok, before} <- number(params["before_revision"], 2_147_483_647),
         {:ok, pages} <- pages(params) do
      {:ok,
       Map.merge(pages, %{
         "contact_id" => params["contact_id"],
         "revision" => revision,
         "before_revision" => before
       })}
    else
      _ -> {:error, :invalid_contact_record_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_contact_record_query}

  def load(%Scope{} = scope, mission, params) do
    org = scope.organization_id
    mid = mission.mission_id

    with {:ok, q} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, kind, scheduled, realized} <- subject(org, mid, q["contact_id"]),
         {:ok, review, history} <- history(org, mid, scheduled, q),
         {:ok, origin} <- origin(org, mid, scheduled, review) do
      q = Map.put(q, "revision", review && review.revision)

      {:ok,
       %{
         record:
           ContactRecordProjection.project(
             scope,
             mid,
             %{
               kind: kind,
               scheduled: scheduled,
               realized: realized,
               review: review,
               history: history,
               origin: origin
             },
             q
           )
       }}
    end
  end

  defp subject(org, mission, id) do
    case {Contacts.fetch_scheduled_contact(org, mission, id),
          Contacts.fetch_realized_contact(org, mission, id)} do
      {{:ok, scheduled}, {:error, :realized_contact_not_found}} ->
        with {:ok, realized} <- linked_realized(org, mission, scheduled),
             do: {:ok, :scheduled, scheduled, realized}

      {{:error, :scheduled_contact_not_found}, {:ok, realized}} ->
        with {:ok, scheduled} <- linked_scheduled(org, mission, realized),
             do: {:ok, :realized, scheduled, realized}

      _ ->
        {:error, :contact_record_not_found}
    end
  end

  defp linked_realized(_, _, %{realized_contact_id: nil}), do: {:ok, nil}

  defp linked_realized(org, mission, scheduled) do
    with {:ok, realized} <-
           Contacts.fetch_realized_contact(org, mission, scheduled.realized_contact_id),
         true <- realized.scheduled_contact_id == scheduled.scheduled_contact_id do
      {:ok, realized}
    else
      _ -> {:error, :contact_record_lineage_unavailable}
    end
  end

  defp linked_scheduled(_, _, %{scheduled_contact_id: nil}), do: {:ok, nil}

  defp linked_scheduled(org, mission, realized),
    do: Contacts.fetch_scheduled_contact(org, mission, realized.scheduled_contact_id)

  defp history(_, _, nil, %{"revision" => nil, "before_revision" => nil}),
    do: {:ok, nil, %{entries: [], next: nil}}

  defp history(_, _, nil, _), do: {:error, :contact_has_no_schedule_history}

  defp history(org, mission, scheduled, q) do
    revision = q["revision"] || scheduled.current_revision

    with true <- revision <= scheduled.current_revision,
         {:ok, review} <-
           Contacts.fetch_scheduled_contact_revision(
             org,
             mission,
             scheduled.scheduled_contact_id,
             revision
           ),
         {:ok, history} <-
           Contacts.list_scheduled_contact_revisions_page(
             org,
             mission,
             scheduled.scheduled_contact_id,
             revision,
             q["before_revision"]
           ) do
      {:ok, review, history}
    else
      false -> {:error, :future_contact_revision}
      {:error, _} = error -> error
    end
  end

  defp origin(_, _, _, nil), do: {:ok, nil}
  defp origin(_, _, _, %{provider_reservation_change_id: nil}), do: {:ok, nil}

  defp origin(org, mission, scheduled, review) do
    with {:ok, change} <-
           Contacts.fetch_provider_change(org, review.provider_reservation_change_id),
         true <- change.mission_id == mission,
         {:ok, reservation} <-
           Contacts.fetch_provider_reservation(org, mission, change.provider_reservation_id),
         true <- reservation.scheduled_contact_id == scheduled.scheduled_contact_id do
      {:ok,
       %{
         change_id: change.provider_reservation_change_id,
         reservation_id: reservation.provider_reservation_id,
         provider_revision: change.provider_revision,
         proposal_hash: change.proposal_hash
       }}
    else
      _ -> {:error, :contact_revision_origin_unavailable}
    end
  end

  defp pages(params) do
    Enum.reduce_while(@pages, {:ok, %{}}, fn key, {:ok, acc} ->
      case number(Map.get(params, key, "1"), 1_000_000) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        _ -> {:halt, {:error, :invalid_page}}
      end
    end)
  end

  defp number(nil, _), do: {:ok, nil}

  defp number(v, max) do
    with true <- Regex.match?(~r/\A[1-9][0-9]{0,9}\z/, v),
         {n, ""} when n <= max <- Integer.parse(v),
         do: {:ok, n},
         else: (_ -> {:error, :invalid_number})
  end

  defp identifier?(v) when is_binary(v) and byte_size(v) in 1..240,
    do: String.valid?(v) and not Regex.match?(~r/[\x00-\x20\x7f]/, v)

  defp identifier?(_), do: false
end
