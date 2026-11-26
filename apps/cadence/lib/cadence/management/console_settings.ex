defmodule Cadence.Management.ConsoleSettings do
  @moduledoc """
  Console Settings (ST1) for a mission or the organization (`mission_id`
  nil). The sections come from `Cadence.Management.Settings` (its registry,
  so new domain sections show up), plus `cadence.configuration`. Each is
  shown as kind-schema fields over the section's `value` document. A section
  the console has no fields for is left out.

  Every section stores `%{"value" => map, "allow_override" => bool}` for the
  organization and `%{"value" => map | nil}` for a mission: only the fields
  it sets, the rest follow the organization (nil inherits all of them).
  Writes go through the section's own provider, which validates.
  """

  alias Cadence.Auth.{Scope, SettingsAccess}

  alias Cadence.Management.{
    ApprovalSettingAccess,
    ConfigurationSettingsSection,
    Settings,
    SettingsHistory
  }

  @configuration %{
    id: "cadence.configuration",
    title: "Configuration",
    description: "How applying a change set reaches the running mission."
  }

  @spec load(Scope.t(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def load(%Scope{} = scope, mission_id) do
    with {:ok, %{sections: registered}} <- Settings.load(scope, mission_id, "cadence.governance") do
      sections =
        (registered ++ [@configuration])
        |> Enum.filter(&Map.has_key?(fields(), &1.id))
        |> Enum.flat_map(&section(scope, mission_id, &1))

      {:ok,
       %{
         sections: sections,
         permissions:
           if(SettingsAccess.authorize(scope, :manage_settings, mission_id) == :ok,
             do: ["settings.edit"],
             else: []
           )
       }}
    end
  end

  @doc """
  Saves `values` (`%{path => value | nil}`) into a section. For a mission, a value sets that
  field for the mission and nil inherits it again (the override keeps only the fields it sets);
  for the organization, `allow_override` is a field too. `expected_version` must match the
  section's current version.
  """
  @spec save(Scope.t(), binary() | nil, binary(), map(), integer() | nil) ::
          {:ok, %{version: pos_integer(), state: :active}} | {:error, term()}
  def save(scope, mission_id, section_id, values, expected_version, opts \\ [])

  def save(%Scope{} = scope, mission_id, section_id, values, expected_version, opts)
      when is_map(values) do
    with {:ok, field_list} <- section_fields(section_id),
         :ok <- known_paths(values, field_list, mission_id),
         {:ok, snapshot} <- snapshot(scope, mission_id, section_id),
         :ok <- current_version(snapshot, expected_version),
         {:ok, _revision} <-
           write(
             scope,
             mission_id,
             section_id,
             snapshot.token,
             input(snapshot, values, mission_id),
             opts
           ) do
      {:ok, %{version: snapshot.version + 1, state: :active}}
    else
      # A concurrent save moved the section between the read and the write: the same 409 as a
      # stale expected_version, with the version it is now.
      {:error, :settings_changed} -> changed(scope, mission_id, section_id)
      other -> other
    end
  end

  def save(_scope, _mission_id, _section_id, _values, _expected, _opts),
    do: {:error, {:invalid_params, %{values: "must be an object"}}}

  defp changed(scope, mission_id, section_id) do
    case snapshot(scope, mission_id, section_id) do
      {:ok, %{version: version}} -> {:error, {:version_conflict, version}}
      _unreadable -> {:error, :settings_changed}
    end
  end

  # -- fields --------------------------------------------------------------------------------

  defp fields do
    %{
      "cadence.governance" => [
        enum(
          "approval_requirement",
          "Approval for changes and app activations",
          [
            {"direct", "Applies without approval"},
            {"independent", "Needs a second person's approval"}
          ],
          help:
            "Covers change sets in Setup › Changes, spacecraft configuration reviews, and app " <>
              "settings that need activation, such as decom. App settings that save " <>
              "immediately, such as limits, aren't covered."
        )
      ],
      "commanding.defaults" => [
        enum("shelf", "Command shelf", [{"expanded", "Expanded"}, {"minimized", "Minimized"}])
      ],
      "cadence.pass_review" => [
        number("pass_realized_threshold", "A pass counts as realized at",
          help: "The share of its planned window it must fly."
        ),
        number("realization_target", "Fleet realization target")
      ],
      "cadence.configuration" => [
        field(
          "profile_framing_generations",
          "Profile framing changes reach the runtime",
          :boolean,
          help: "Applying a change to a profile's framing also activates it for its spacecraft."
        )
      ]
    }
  end

  @allow_override %{
    path: "allow_override",
    label: "Missions may override",
    type: :boolean,
    unit: nil,
    enum: nil,
    range: nil,
    required: false,
    help: nil,
    visible_when: nil
  }

  defp section_fields(section_id) do
    case Map.fetch(fields(), section_id) do
      {:ok, list} -> {:ok, list}
      :error -> {:error, :unknown_settings_section}
    end
  end

  defp enum(path, label, options, opts \\ []),
    do:
      field(path, label, :enum,
        enum: Enum.map(options, fn {value, text} -> %{value: value, label: text} end),
        help: Keyword.get(opts, :help)
      )

  # Shares between 0 and 1: the console shows and accepts percentages (unit "ratio").
  defp number(path, label, opts \\ []),
    do:
      field(
        path,
        label,
        :number,
        opts |> Keyword.put(:range, %{min: 0, max: 1}) |> Keyword.put(:unit, "ratio")
      )

  defp field(path, label, type, opts) do
    %{
      path: path,
      label: label,
      type: type,
      unit: Keyword.get(opts, :unit),
      enum: Keyword.get(opts, :enum),
      range: Keyword.get(opts, :range),
      required: false,
      help: Keyword.get(opts, :help),
      visible_when: nil
    }
  end

  # -- read ----------------------------------------------------------------------------------

  # A section whose provider can't be read is left out (Settings logs the failure), not a 500.
  defp section(scope, mission_id, %{id: id} = section) do
    case snapshot(scope, mission_id, id) do
      {:ok, snapshot} -> [section_view(scope, mission_id, section, snapshot)]
      {:error, _reason} -> []
    end
  end

  defp section_view(scope, mission_id, %{id: id} = section, snapshot) do
    effective = snapshot.effective || %{}
    inherited = snapshot.organization_default || %{}
    set_here = if snapshot.source == "overridden", do: snapshot.saved || %{}, else: %{}

    fields =
      Enum.map(fields()[id], fn field ->
        Map.merge(field, %{
          value: effective[field.path],
          source: source(mission_id, Map.has_key?(set_here, field.path)),
          inherited_value: if(mission_id, do: inherited[field.path])
        })
      end)

    fields =
      if is_nil(mission_id),
        do:
          fields ++
            [
              Map.merge(@allow_override, %{
                value: snapshot.allow_override,
                source: "organization",
                inherited_value: nil
              })
            ],
        else: fields

    %{
      key: id,
      title: section.title,
      purpose: section.description,
      fields: governed(scope, mission_id, id, fields, snapshot),
      locked: mission_id != nil and snapshot.source == "enforced",
      version: version(scope.organization_id, mission_id, id, snapshot)
    }
  end

  # #233: the approval setting's fields say what THIS viewer may change (allowed_values,
  # can_inherit); other fields carry neither key (no field-level limit).
  defp governed(scope, mission_id, "cadence.governance", fields, snapshot),
    do:
      Enum.map(
        fields,
        &Map.merge(&1, ApprovalSettingAccess.flags(scope, mission_id, &1.path, snapshot))
      )

  defp governed(_scope, _mission_id, _id, fields, _snapshot), do: fields

  # Per field: a mission's field is its own only when its override sets that path.
  defp source(nil, _set_here?), do: "organization"
  defp source(_mission, true), do: "mission"
  defp source(_mission, false), do: "organization"

  defp version(_organization_id, _mission_id, _id, %{version: 0}), do: nil

  defp version(organization_id, mission_id, id, snapshot) do
    case SettingsHistory.list(organization_id, mission_id, id) do
      [latest | _] ->
        %{version: snapshot.version, at: latest.saved_at, actor: %{name: latest.actor}}

      [] ->
        %{version: snapshot.version, at: nil, actor: nil}
    end
  end

  # -- write ---------------------------------------------------------------------------------

  defp snapshot(scope, mission_id, "cadence.configuration") do
    with :ok <- SettingsAccess.authorize(scope, :read_settings, mission_id),
         do:
           {:ok,
            ConfigurationSettingsSection.settings_snapshot(scope.organization_id, mission_id)}
  end

  defp snapshot(scope, mission_id, section_id) do
    with {:ok, %{settings: settings}} <- Settings.load(scope, mission_id, section_id) do
      if is_map(settings), do: {:ok, settings}, else: {:error, :settings_unavailable}
    end
  end

  defp write(scope, mission_id, "cadence.configuration", token, input, _opts),
    do: ConfigurationSettingsSection.save(scope, mission_id, token, input)

  defp write(scope, mission_id, section_id, token, input, opts),
    do: Settings.save(scope, mission_id, section_id, token, input, opts)

  defp known_paths(values, field_list, mission_id) do
    allowed =
      Enum.map(field_list, & &1.path) ++ if(is_nil(mission_id), do: ["allow_override"], else: [])

    case Map.keys(values) -- allowed do
      [] ->
        :ok

      unknown ->
        {:error, {:invalid_params, Map.new(unknown, &{&1, "is not a field of this section"})}}
    end
  end

  defp current_version(_snapshot, nil), do: :ok
  defp current_version(%{version: version}, version), do: :ok
  defp current_version(%{version: version}, _expected), do: {:error, {:version_conflict, version}}

  # The organization keeps every field (nil is rejected by the provider); a mission stores only
  # the fields it sets (nil removes one), and clears its override when none is left.
  defp input(snapshot, values, nil) do
    value =
      Map.merge(snapshot.saved || snapshot.effective || %{}, Map.delete(values, "allow_override"))

    %{
      "value" => value,
      "allow_override" => Map.get(values, "allow_override", snapshot.allow_override)
    }
  end

  defp input(snapshot, values, _mission) do
    set =
      (snapshot.saved || %{})
      |> Map.merge(values)
      |> Map.reject(fn {_path, value} -> is_nil(value) end)

    if set == %{}, do: %{"value" => nil}, else: %{"value" => set}
  end
end
