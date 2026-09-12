defmodule Cadence.Reads.ApplicationSurfaces.Planning.ReservationProjection do
  @moduledoc false
  alias Cadence.Auth.Policy

  @fields ~w(provider_contact_ref opportunity_ref spacecraft_ref ground_station_ref antenna_or_service_pool_ref service_profile_ref delivery_profile_ref starts_at ends_at status pass_phase delivery_state status_reason)

  def project(scope, r, selected, query, changes, audit) do
    %{
      contract_version: 1,
      context: %{organization_id: scope.organization_id, mission_id: r.mission_id},
      reservation: %{
        id: r.provider_reservation_id,
        provider_revision: r.provider_revision,
        lifecycle_state: to_string(r.lifecycle_state),
        provider_id: r.provider_id,
        provider_version: r.provider_version,
        spacecraft_id: r.spacecraft_id,
        transport_id: r.transport_id,
        transport_version: r.transport_version,
        plan_id: r.contact_plan_id,
        plan_version: r.contact_plan_version,
        requirement_id: r.contact_requirement_id,
        requirement_version: r.contact_requirement_version,
        starts_at: iso(r.starts_at),
        ends_at: iso(r.ends_at),
        scheduled_contact_id: r.scheduled_contact_id,
        last_reconciled_at: iso(r.last_reconciled_at)
      },
      permissions: %{
        decide:
          Policy.authorize(scope, :approve_provider_changes, %{
            organization_id: scope.organization_id,
            mission_id: r.mission_id
          }) == :ok
      },
      query: query,
      values:
        Enum.map(@fields, fn f ->
          %{
            field: f,
            requested: scalar(r.requested_snapshot_document[f]),
            confirmed: scalar(r.provider_confirmed_snapshot_document[f]),
            accepted: scalar(r.cadence_accepted_snapshot_document[f])
          }
        end),
      selected: if(selected, do: review(selected)),
      changes: %{entries: Enum.map(changes.entries, &summary/1), next: changes.next},
      audit: %{entries: Enum.map(audit.entries, &audit/1), next: audit.next}
    }
  end

  defp summary(c),
    do: %{
      id: c.provider_reservation_change_id,
      provider_revision: c.provider_revision,
      proposal_hash: c.proposal_hash,
      lifecycle_state: to_string(c.lifecycle_state),
      classification: to_string(c.classification),
      recorded_at: iso(c.inserted_at)
    }

  defp review(c) do
    fields =
      c.changed_fields_document
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {field, values} ->
        compare(field, values["before"], values["after"])
      end)

    summary(c)
    |> Map.merge(%{
      from_provider_revision: c.from_provider_revision,
      policy_version: c.policy_version,
      actionable: c.actionable,
      already_effective: c.already_effective,
      deadline_at: iso(c.deadline_at),
      decided_at: iso(c.decided_at),
      fields: fields,
      review_complete: Enum.all?(fields, & &1.visible)
    })
  end

  @extension_leaves ~w(extensions.cost extensions.estimated_capacity.value extensions.estimated_capacity.unit extensions.provider_change.effective extensions.provider_change.rejectable extensions.provider_change.deadline_at)
  @extension_maps ~w(extensions extensions.estimated_capacity extensions.provider_change)

  defp compare(path, before, after_value) when path in @extension_maps do
    if (is_map(before) or is_nil(before)) and (is_map(after_value) or is_nil(after_value)) do
      before = before || %{}
      after_value = after_value || %{}

      (Map.keys(before) ++ Map.keys(after_value))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.filter(&(before[&1] != after_value[&1]))
      |> Enum.flat_map(&compare(path <> "." <> &1, before[&1], after_value[&1]))
    else
      [comparison("additional_provider_data", before, after_value, false)]
    end
  end

  defp compare(field, before, after_value) do
    visible =
      (field in @fields or field in @extension_leaves) and scalar?(before) and
        scalar?(after_value)

    [
      comparison(
        if(visible, do: field, else: "additional_provider_data"),
        before,
        after_value,
        visible
      )
    ]
  end

  defp comparison(field, before, after_value, visible),
    do: %{
      field: field,
      before: if(visible, do: scalar(before), else: "Restricted provider data"),
      after: if(visible, do: scalar(after_value), else: "Restricted provider data"),
      visible: visible
    }

  defp audit(a),
    do: %{
      id: a.provider_audit_entry_id,
      action: String.slice(a.action, 0, 120),
      outcome: String.slice(a.outcome, 0, 120),
      recorded_at: iso(a.recorded_at),
      change_id: a.references.provider_change_id
    }

  defp iso(nil), do: nil
  defp iso(t), do: DateTime.to_iso8601(t)
  defp scalar(nil), do: "—"
  defp scalar(v) when is_binary(v), do: if(scalar?(v), do: v, else: "Unavailable value")
  defp scalar(v) when is_number(v) or is_boolean(v), do: to_string(v)
  defp scalar(_), do: "Structured provider value"
  defp scalar?(v) when is_binary(v), do: String.valid?(v) and byte_size(v) <= 512
  defp scalar?(v), do: is_nil(v) or is_number(v) or is_boolean(v)
end
