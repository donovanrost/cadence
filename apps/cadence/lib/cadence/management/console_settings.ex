defmodule Cadence.Management.ConsoleSettings do
  @moduledoc """
  Console Settings (ST1) for a mission or the organization (`mission_id`
  nil). The sections come from `Cadence.Management.Settings` (its registry,
  so new domain sections show up), plus `cadence.configuration`. Each is
  shown as kind-schema fields over the section's `value` document. A section
  the console has no fields for is left out.

  Every section stores `%{"value" => map, "allow_override" => bool}` for the
  organization and `%{"value" => map | nil}` for a mission (nil means
  inherit); writes go through the section's own provider, which validates.
  """

  alias Cadence.Auth.{Scope, SettingsAccess}
  alias Cadence.Management.{ConfigurationSettingsSection, Settings}
  alias Cadence.Platform.ScopedSettings

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
        |> Enum.map(&section(scope, mission_id, &1))

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
  Saves `values` (`%{path => value | nil}`) into a section. For a mission, a nil value
  inherits that field and all nils clear the override; for the organization, `allow_override`
  is a field too. `expected_version` must match the section's current version.
  """
  @spec save(Scope.t(), binary() | nil, binary(), map(), integer() | nil) ::
          {:ok, %{version: pos_integer(), state: :active}} | {:error, term()}
  def save(%Scope{} = scope, mission_id, section_id, values, expected_version)
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
             input(snapshot, values, mission_id)
           ) do
      {:ok, %{version: snapshot.version + 1, state: :active}}
    end
  end

  def save(_scope, _mission_id, _section_id, _values, _expected),
    do: {:error, {:invalid_params, %{values: "must be an object"}}}

  # -- fields --------------------------------------------------------------------------------

  defp fields do
    %{
      "cadence.governance" => [
        enum("approval_requirement", "Applying a change set", [
          {"direct", "Applies directly"},
          {"independent", "Needs a second person's approval"}
        ])
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

  defp enum(path, label, options),
    do:
      field(path, label, :enum,
        enum: Enum.map(options, fn {value, text} -> %{value: value, label: text} end)
      )

  defp number(path, label, opts \\ []),
    do: field(path, label, :number, Keyword.put(opts, :range, %{min: 0, max: 1}))

  defp field(path, label, type, opts) do
    %{
      path: path,
      label: label,
      type: type,
      unit: nil,
      enum: Keyword.get(opts, :enum),
      range: Keyword.get(opts, :range),
      required: false,
      help: Keyword.get(opts, :help),
      visible_when: nil
    }
  end

  # -- read ----------------------------------------------------------------------------------

  defp section(scope, mission_id, %{id: id} = section) do
    {:ok, snapshot} = snapshot(scope, mission_id, id)
    effective = snapshot.effective || %{}
    inherited = snapshot.organization_default || %{}

    fields =
      Enum.map(fields()[id], fn field ->
        Map.merge(field, %{
          value: effective[field.path],
          source: source(mission_id, snapshot.source),
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
      fields: fields,
      locked: mission_id != nil and snapshot.source == "enforced",
      version: version(scope.organization_id, mission_id, id, snapshot)
    }
  end

  defp source(nil, _source), do: "organization"
  defp source(_mission, "overridden"), do: "mission"
  defp source(_mission, _inherited), do: "organization"

  defp version(_organization_id, _mission_id, _id, %{version: 0}), do: nil

  defp version(organization_id, mission_id, id, snapshot) do
    case ScopedSettings.history(organization_id, mission_id, id) do
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

  defp write(scope, mission_id, "cadence.configuration", token, input),
    do: ConfigurationSettingsSection.save(scope, mission_id, token, input)

  defp write(scope, mission_id, section_id, token, input),
    do: Settings.save(scope, mission_id, section_id, token, input)

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

  # The organization keeps every field (nil is rejected by the provider); a mission inherits
  # nil fields, and clears its override when none is left.
  defp input(snapshot, values, nil) do
    value =
      Map.merge(snapshot.saved || snapshot.effective || %{}, Map.delete(values, "allow_override"))

    %{
      "value" => value,
      "allow_override" => Map.get(values, "allow_override", snapshot.allow_override)
    }
  end

  defp input(snapshot, values, _mission) do
    base = snapshot.saved || snapshot.organization_default || %{}
    merged = Map.merge(base, values)

    if Enum.all?(values, fn {_path, value} -> is_nil(value) end) and map_size(values) > 0,
      do: %{"value" => nil},
      else: %{
        "value" =>
          Map.new(merged, fn
            {path, nil} -> {path, (snapshot.organization_default || %{})[path]}
            pair -> pair
          end)
      }
  end
end
