defmodule Cadence.Spacecraft.ConfigKinds.ApidCompatibility do
  @moduledoc """
  Derived check (L22): HOLDs when an apply would change which APIDs a spacecraft decodes. A
  profile's or override's `handled_apids` (nil = all of the catalog's APIDs) governs spacecraft
  whose profile sets their catalog, so a change set can widen or narrow decode without naming
  APIDs (a catalog move, a default expanded). Nothing changes unseen (ux U40 (d)/(e)):

  - `handled_apids_change` (acknowledge): the spacecraft and the APIDs they start or stop
    decoding;
  - `handled_apids_not_in_catalog` (blocking): a list names APIDs the catalog doesn't define.

  Never staged. The configured generation builder reads what would change.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.ConfigurationSettings

  @impl true
  def kind, do: "apid_compatibility"

  @impl true
  def id_prefix, do: "apid"

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
  def summary(_action, _previous, _proposed), do: "Handled APIDs"

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
         builder when builder != nil <- Application.get_env(:cadence, :configuration_generation) do
      impact = builder.apid_impact(organization_id, mission_id, touched)
      {stray, moved} = Enum.split_with(impact.changes, fn {_id, change} -> change.stray != [] end)
      stray_items(stray, impact) ++ change_items(moved, impact)
    else
      _nothing -> []
    end
  end

  defp change_items([], _impact), do: []

  defp change_items([{id, change}], impact),
    do: [
      item(:handled_apids_change, [id], false, %{
        changes: [detail(id, change, impact)],
        sentence: change_sentence(impact.names[id], change)
      })
    ]

  defp change_items(moved, impact) do
    ids = Enum.map(moved, &elem(&1, 0))

    [
      item(:handled_apids_change, ids, false, %{
        changes: Enum.map(moved, fn {id, change} -> detail(id, change, impact) end),
        sentence: changes_sentence(length(ids))
      })
    ]
  end

  # One blocking HOLD per catalog, naming the spacecraft and the APIDs it doesn't define.
  defp stray_items([], _impact), do: []

  defp stray_items(stray, impact) do
    stray
    |> Enum.group_by(fn {id, _change} -> impact.catalogs[id] end)
    |> Enum.map(fn {catalog, group} ->
      named = Enum.map(group, fn {id, change} -> {impact.names[id], change.stray} end)

      item(:handled_apids_not_in_catalog, Enum.map(group, &elem(&1, 0)), true, %{
        catalog: catalog,
        changes: Enum.map(group, fn {id, change} -> detail(id, change, impact) end),
        sentence: stray_sentence(named, Map.get(impact.labels, catalog, catalog))
      })
    end)
  end

  ## HOLD sentences (ux U40 (e) and (d))

  @doc "The `handled_apids_change` sentence for one spacecraft."
  def change_sentence(name, %{from: from, to: to}) do
    added = to -- from
    removed = from -- to

    cond do
      removed == [] ->
        "#{name} will also decode APIDs #{list(added)} after this is applied " <>
          "(today only #{list(from)})."

      added == [] ->
        "#{name} will stop decoding APIDs #{list(removed)} after this is applied."

      true ->
        "#{name} will start decoding #{list(added)} and stop decoding #{list(removed)} " <>
          "after this is applied."
    end
  end

  @doc "The sentence for several spacecraft."
  def changes_sentence(count),
    do: "#{count} spacecraft will decode different APIDs after this is applied."

  @doc "The `handled_apids_not_in_catalog` sentence."
  def stray_sentence([{name, stray}], catalog_label),
    do:
      "#{name} handles APIDs #{list(stray)}, which #{catalog_label} doesn't define. " <>
        "Change its handled APIDs first."

  def stray_sentence(named, catalog_label) do
    stray = named |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    "#{length(named)} spacecraft handle APIDs that #{catalog_label} doesn't define " <>
      "(#{list(stray)}). Change their handled APIDs first."
  end

  @doc ~s(APIDs as ux writes them: 0x2A, at most 5, then "and N more"; empty reads "none".)
  def list([]), do: "none"

  def list(apids) do
    {shown, rest} = apids |> Enum.sort() |> Enum.split(5)
    words = Enum.map(shown, &hex/1)

    case rest do
      [] -> join(words)
      _more -> Enum.join(words, ", ") <> " and #{length(rest)} more"
    end
  end

  defp join([one]), do: one
  defp join(words), do: Enum.join(Enum.drop(words, -1), ", ") <> " and " <> List.last(words)

  defp hex(apid), do: "0x" <> (apid |> Integer.to_string(16) |> String.pad_leading(2, "0"))

  defp detail(id, change, impact),
    do: %{
      spacecraft_id: id,
      name: impact.names[id],
      added: change.to -- change.from,
      removed: change.from -- change.to,
      stray: change.stray
    }

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
end
