defmodule Cadence.Spacecraft.ConfigKinds.CatalogCompatibility do
  @moduledoc """
  Derived check (DECISIONS #36/#65): a change set that moves spacecraft onto another catalog
  produces a runtime generation (telemetry decode and command models follow the new catalog).
  It holds for review:

  - `catalog_change`: which spacecraft move from which catalog to which (acknowledge);
  - `catalog_cancels_commands`: commands waiting to release on them, which the apply cancels
    (`catalog_changed`) rather than let them fail closed at release (acknowledge);
  - `catalog_command_in_flight`: a command releasing or radiating on them right now. Blocking:
    the apply waits for it to finish;
  - `catalog_configuration_pending`: a newer spacecraft configuration that isn't active yet.
    Blocking: activate or discard it first.

  Never staged. The configured generation builder decides what changes, as for framing.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.ConfigurationSettings

  @impl true
  def kind, do: "catalog_compatibility"

  @impl true
  def id_prefix, do: "catalog"

  @impl true
  def load(_organization_id, _mission_id, _ids), do: %{}

  @impl true
  def normalize(_action, _id, _document), do: {:error, [F.error("", "This check isn't staged")]}

  @impl true
  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  @impl true
  def write(_organization_id, _mission_id, _action, _id, _previous, _proposed, _options),
    do: {:error, :not_staged}

  @impl true
  def summary(_action, _previous, _proposed), do: "Catalog compatibility"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  @impl true
  def holds(organization_id, mission_id, entries) do
    touched =
      entries
      |> Enum.filter(&(&1.kind in ["spacecraft", "spacecraft_override"] and &1.op == :update))
      |> Enum.map(& &1.entity_id)
      |> Enum.uniq()

    with [_ | _] <- touched,
         true <- ConfigurationSettings.profile_framing_generations?(organization_id, mission_id),
         builder when builder != nil <- Application.get_env(:cadence, :configuration_generation),
         %{changes: changes} = impact when map_size(changes) > 0 <-
           builder.catalog_impact(organization_id, mission_id, touched) do
      change_items(changes, Map.get(impact, :labels, %{})) ++
        waiting_items(impact.waiting) ++
        in_flight_items(impact.in_flight) ++
        pending_items(impact.pending) ++
        unapproved_items(Map.get(impact, :unapproved, []), Map.get(impact, :labels, %{}))
    else
      _nothing -> []
    end
  end

  # Revisions read "rev N" (qa: raw ids read badly); the builder names them.
  defp change_items(changes, labels) do
    label = fn id -> if id, do: Map.get(labels, id, id), else: "none" end

    changes
    |> Enum.group_by(fn {_id, change} -> {change.from, change.to} end, &elem(&1, 0))
    |> Enum.map(fn {{from, to}, ids} ->
      item(:catalog_change, ids, false, %{
        from: from,
        to: to,
        sentence:
          "#{count(ids)} will decode telemetry and build commands with catalog " <>
            "#{label.(to)} instead of #{label.(from)}."
      })
    end)
  end

  # #92 (a): a generation can't introduce a mission model nobody approved (Control.ModelApprovalGate).
  defp unapproved_items(targets, labels) do
    for target <- targets do
      item(:mission_model_not_approved, target.spacecraft_ids, true, %{
        details: %{
          catalog_revision_id: target.catalog_revision_id,
          mission_model_revision_id: target.mission_model_revision_id
        },
        sentence:
          "Catalog #{Map.get(labels, target.catalog_revision_id, target.catalog_revision_id)}'s " <>
            "mission model isn't approved yet, so #{count(target.spacecraft_ids)} can't move to it. " <>
            "An organization administrator approves it first."
      })
    end
  end

  defp waiting_items([]), do: []

  defp waiting_items(requests) do
    [
      item(:catalog_cancels_commands, [], false, %{
        requests: requests,
        sentence:
          "#{plural(length(requests), "command")} waiting to release on these spacecraft " <>
            "will be canceled when this applies (catalog changed)."
      })
    ]
  end

  defp in_flight_items([]), do: []

  defp in_flight_items(requests) do
    [
      item(:catalog_command_in_flight, [], true, %{
        requests: requests,
        sentence:
          "#{plural(length(requests), "command")} on these spacecraft #{verb(requests)} " <>
            "releasing or radiating now. Apply when #{if length(requests) == 1, do: "it", else: "they"} finish."
      })
    ]
  end

  defp pending_items([]), do: []

  defp pending_items(ids) do
    [
      item(:catalog_configuration_pending, ids, true, %{
        sentence:
          "#{count(ids)} #{if length(ids) == 1, do: "has", else: "have"} a newer configuration " <>
            "that isn't active yet. Activate or discard it before the catalog moves."
      })
    ]
  end

  defp item(reason, spacecraft_ids, blocking, extra) do
    Map.merge(
      %{
        op_id: nil,
        change_id: nil,
        kind: "spacecraft",
        entity_id: List.first(spacecraft_ids),
        reason: reason,
        spacecraft_ids: spacecraft_ids,
        blocking: blocking
      },
      extra
    )
  end

  defp count([_one]), do: "1 spacecraft"
  defp count(ids), do: "#{length(ids)} spacecraft"

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  defp verb([_one]), do: "is"
  defp verb(_many), do: "are"
end
