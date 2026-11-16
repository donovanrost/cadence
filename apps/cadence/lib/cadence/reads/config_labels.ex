defmodule Cadence.Reads.ConfigLabels do
  @moduledoc """
  Display fields for change-set previews and revision entries (fe-setup / ux): each item gets
  `entity_name`, and each changed path gets the kind schema's `label` and `unit`, so the console
  can say "Earendil Block 1 · TM frame length is 1,024 bytes now, not 900 bytes as r8 left it".
  Names come from the documents (`display_name`), else the entity's current document; a
  spacecraft-keyed kind (overrides, routes) takes the spacecraft's name. Unknown ones stay nil.

  Labels come from the kind's edit schema (`ConfigKindSchema`); kinds without one fall back to the
  labels their editors already use: a profile's fields from `Cadence.SpacecraftType.Schema`
  (`frame_parameters.frame_size` is "TM frame length", bytes), an override's from the profile
  field it overrides, and a spacecraft's from a small map. A label may carry `format`
  (`"version"`: show 4 as "v4").
  """

  alias Cadence.Configuration.Kinds
  alias Cadence.Reads.ConfigKindSchema
  alias Cadence.SpacecraftType.Schema

  @spacecraft_keyed ~w(spacecraft_override spacecraft_routes)

  @doc "Adds display fields to a preview's conflict items and diffs."
  @spec preview(binary(), binary(), map() | nil) :: map() | nil
  def preview(_organization_id, _mission_id, nil), do: nil

  def preview(organization_id, mission_id, preview) do
    items = Enum.flat_map(preview.checks, & &1.items) ++ preview.diffs
    names = names(organization_id, mission_id, items, %{})
    fields = schemas(organization_id, mission_id, items)

    %{
      preview
      | checks:
          Enum.map(preview.checks, fn check ->
            %{check | items: Enum.map(check.items, &decorate(&1, names, fields))}
          end),
        diffs: Enum.map(preview.diffs, &decorate(&1, names, fields))
    }
  end

  @doc "Adds display fields to a revision's entries (or a compare's, which carry no documents)."
  @spec revision(binary(), binary(), map()) :: map()
  def revision(organization_id, mission_id, %{entries: entries} = revision) do
    documented =
      Map.new(entries, fn entry ->
        {{entry.kind, entry.entity_id},
         name_of(Map.get(entry, :after)) || name_of(Map.get(entry, :before))}
      end)

    names = names(organization_id, mission_id, entries, documented)
    fields = schemas(organization_id, mission_id, entries)
    %{revision | entries: Enum.map(entries, &decorate(&1, names, fields))}
  end

  def revision(_organization_id, _mission_id, revision), do: revision

  defp decorate(%{kind: kind, entity_id: id} = item, names, fields) do
    labels = Map.get(fields, kind, %{})

    item
    |> Map.put(:entity_name, Map.get(names, {kind, id}))
    |> label_list(:paths, labels)
    |> label_list(:fields, labels)
  end

  defp decorate(item, _names, _fields), do: item

  defp label_list(item, key, labels) do
    case Map.get(item, key) do
      list when is_list(list) ->
        Map.put(item, key, Enum.map(list, &label(&1, labels)))

      _none ->
        item
    end
  end

  defp label(%{path: path} = entry, labels) do
    field = Map.get(labels, path, %{})

    entry
    |> Map.merge(%{label: field[:label], unit: field[:unit]})
    |> then(&if(field[:format], do: Map.put(&1, :format, field.format), else: &1))
  end

  defp label(entry, _labels), do: entry

  defp names(organization_id, mission_id, items, known) do
    items
    |> Enum.filter(&(is_map_key(&1, :kind) and is_map_key(&1, :entity_id)))
    |> Enum.reject(&Map.get(known, {&1.kind, &1.entity_id}))
    |> Enum.group_by(&lookup_kind(&1.kind), & &1.entity_id)
    |> Enum.reduce(known, fn {kind, ids}, acc ->
      Map.merge(acc, load_names(organization_id, mission_id, kind, Enum.uniq(ids), items))
    end)
  end

  # Overrides and routes are keyed by the spacecraft: name them after it.
  defp lookup_kind(kind) when kind in @spacecraft_keyed, do: "spacecraft"
  defp lookup_kind(kind), do: kind

  defp load_names(organization_id, mission_id, kind, ids, items) do
    loaded =
      case Kinds.fetch(kind) do
        {:ok, module} -> module.load(organization_id, mission_id, ids)
        _unknown -> %{}
      end

    for item <- items,
        lookup_kind(item.kind) == kind,
        name = name_of(Map.get(loaded, item.entity_id)),
        into: %{},
        do: {{item.kind, item.entity_id}, name}
  end

  defp schemas(organization_id, mission_id, items) do
    items
    |> Enum.map(&Map.get(&1, :kind))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn kind ->
      # The edit schema wins where it has the path; the fallback keeps paths it doesn't edit
      # (a spacecraft's metadata.norad_id) and display hints such as `format`.
      case ConfigKindSchema.fields(kind, organization_id, mission_id) do
        {:ok, fields} ->
          schema = Map.new(fields, &{&1.path, &1})

          {kind,
           Map.merge(fallback(kind), schema, fn _path, hint, field -> Map.merge(hint, field) end)}

        _none ->
          {kind, fallback(kind)}
      end
    end)
  end

  @spacecraft [
    %{path: "display_name", label: "Name"},
    %{path: "scid", label: "SCID"},
    %{path: "metadata.norad_id", label: "NORAD ID"},
    %{path: "spacecraft_type_id", label: "Profile"},
    %{path: "spacecraft_type_version", label: "Profile version", format: "version"}
  ]

  defp fallback("spacecraft"), do: Map.new(@spacecraft, &{&1.path, &1})

  defp fallback("spacecraft_profile"),
    do: Map.new([%{path: "display_name", label: "Name"} | profile_fields()], &{&1.path, &1})

  # Override documents are `%{"frame_parameters/frame_size" => %{"value", "reason"}}`.
  defp fallback("spacecraft_override") do
    profile_fields()
    |> Enum.flat_map(fn field ->
      key = String.replace(field.path, ".", "/")

      [
        {key <> ".value", field},
        {key <> ".reason", %{label: field.label <> " override reason"}}
      ]
    end)
    |> Map.new()
  end

  defp fallback(_kind), do: %{}

  defp profile_fields, do: Enum.flat_map(Schema.sections(), & &1.fields)

  # U82: a station reads 'Inuvik · INU' (its name alone without a code); only station documents
  # carry a code.
  defp name_of(%{"display_name" => name, "code" => code})
       when is_binary(name) and is_binary(code) and code != "",
       do: "#{name} · #{code}"

  defp name_of(%{"display_name" => name}) when is_binary(name), do: name
  defp name_of(_document), do: nil
end
