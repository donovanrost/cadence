defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactRecordProjection do
  @moduledoc false

  def project(scope, mission, data, query) do
    %{scheduled: scheduled, realized: realized, review: review, history: history} = data

    %{
      contract_version: 1,
      context: %{organization_id: scope.organization_id, mission_id: mission},
      subject: %{id: query["contact_id"], kind: to_string(data.kind)},
      query: query,
      scheduled: if(scheduled, do: scheduled(scheduled)),
      realized: if(realized, do: realized(realized)),
      review: if(review, do: review(review)),
      origin: data.origin,
      revisions: %{entries: Enum.map(history.entries, &revision/1), next: history.next},
      scheduled_paths: page(paths(scheduled), query["scheduled_paths_page"]),
      realized_paths: page(paths(realized), query["realized_paths_page"]),
      sources: page(sources(review, realized), query["sources_page"]),
      intents: page(intents(scheduled, realized), query["intents_page"])
    }
  end

  defp scheduled(s),
    do: %{
      id: s.scheduled_contact_id,
      current_revision: s.current_revision,
      lifecycle_state: to_string(s.lifecycle_state),
      starts_at: iso(s.starts_at),
      ends_at: iso(s.ends_at),
      realized_id: s.realized_contact_id,
      provider_contact_ref: s.provider_contact_ref
    }

  defp realized(r),
    do: %{
      id: r.realized_contact_id,
      scheduled_id: r.scheduled_contact_id,
      lifecycle_state: to_string(r.lifecycle_state),
      clock_mode: to_string(r.clock_mode),
      realized_at: iso(r.realized_at),
      initial_time: iso(r.initial_time)
    }

  defp revision(r),
    do: %{
      id: r.scheduled_contact_revision_id,
      revision: r.revision,
      created_at: iso(r.created_at),
      created_by: r.created_by,
      provider_change_id: r.provider_reservation_change_id
    }

  defp review(r),
    do:
      Map.merge(revision(r), %{
        starts_at: r.snapshot_document["starts_at"],
        ends_at: r.snapshot_document["ends_at"],
        lifecycle_state: r.snapshot_document["lifecycle_state"],
        provider_contact_ref: r.snapshot_document["provider_contact_ref"]
      })

  defp paths(nil), do: []

  defp paths(contact),
    do:
      Enum.map(contact.paths, fn p ->
        %{
          id: p.path_id,
          direction: to_string(p.direction),
          selection: to_string(p.selection_role),
          source_endpoint_ref: p.source_endpoint_ref,
          provider_binding_count: length(p.provider_bindings),
          transport_binding_count: length(p.transport_bindings)
        }
      end)

  defp sources(review, realized) do
    scheduled = if(review, do: review.snapshot_document["source_endpoint_refs"] || [], else: [])
    actual = if(realized, do: realized.source_endpoint_refs, else: [])
    tagged(scheduled, "reviewed_schedule") ++ tagged(actual, "realized")
  end

  defp intents(scheduled, realized) do
    planned = if(scheduled, do: Enum.map(scheduled.contact_intents, &to_string/1), else: [])
    actual = if(realized, do: Enum.map(realized.contact_intents, &to_string/1), else: [])
    tagged(planned, "current_schedule") ++ tagged(actual, "realized")
  end

  defp tagged(values, kind), do: values |> Enum.uniq() |> Enum.map(&%{id: &1, kind: kind})

  defp page(entries, number) do
    rows = entries |> Enum.drop((number - 1) * 25) |> Enum.take(26)
    %{page: number, more: length(rows) > 25, entries: Enum.take(rows, 25)}
  end

  defp iso(nil), do: nil
  defp iso(t), do: DateTime.to_iso8601(t)
end
