defmodule Cadence.Control.PlanningRequirements do
  @moduledoc """
  Console one-off contact requirements (BACKLOG §8 8g): list, show, create and new version.
  Writes go through `ContactRequirements`, which authorizes, validates and versions them.

  The wire `content` holds the requirement's fields (`Schema.content_keys/0`). On a new version,
  an omitted key carries over from the current version and an explicit `null` clears a nullable
  field (`max_gap_seconds: null` is no limit), as `ContactRequirements` merges them.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    ContactRequirementVersion,
    RequirementListing,
    TemplateDescriptions
  }

  alias Cadence.Control.{ActorRef, PlanningOperations}
  alias Cadence.Control.PlanningRequirements.Schema
  alias Cadence.SpacecraftStore

  # Explicit string -> atom maps, never String.to_existing_atom: an atom may not exist yet when its
  # module hasn't loaded (qa #53, the 11-11 'criteria' class).
  @states %{"active" => :active, "closed" => :closed, "canceled" => :canceled}
  @sources %{"one_off" => :one_off, "template" => :template}
  @default_limit 50
  @max_limit 200
  @max_reason 2_000

  @doc "`{fields, defaults}` for the requirement form."
  @spec schema() :: map()
  def schema, do: %{fields: Schema.fields(), defaults: Schema.defaults()}

  @doc """
  A page of requirements at their current version, most recently changed first. Params:
  `spacecraft_id`, `state`, `source`, `page` (1-based), `limit` (1–#{@max_limit}).
  """
  @spec list(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def list(organization_id, mission_id, params) do
    with {:ok, filters} <- filters(params) do
      %{entries: entries, next_page: next_page} =
        RequirementListing.page(organization_id, mission_id, filters)

      names = names(organization_id, mission_id, Enum.map(entries, &elem(&1, 1).spacecraft_id))

      {:ok,
       %{
         requirements: Enum.map(entries, fn {req, version} -> row(req, version, names) end),
         page: filters.page,
         next_page: next_page
       }}
    end
  end

  @doc """
  'From templates' (fe-setup, ContactPlanning.md P4): per template, how many requirements it
  generated whose window opens on the UTC `day` (`"YYYY-MM-DD"`, default today), and how many of
  those are still active. Templates with none that day are left out.
  """
  @spec by_template(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def by_template(organization_id, mission_id, params) do
    with {:ok, day} <- day(params["day"]) do
      from = DateTime.new!(day, ~T[00:00:00], "Etc/UTC")

      counts =
        RequirementListing.counts_by_template(
          organization_id,
          mission_id,
          from,
          DateTime.add(from, 86_400)
        )

      templates =
        for {template, version} <- ContactRequirementTemplates.list(organization_id, mission_id),
            %{} = counted <- [counts[template.contact_requirement_template_id]] do
          Map.merge(
            %{
              template: %{
                id: template.contact_requirement_template_id,
                name: version.name,
                state: template.lifecycle_state
              }
            },
            counted
          )
        end

      {:ok, %{day: Date.to_iso8601(day), templates: Enum.sort_by(templates, & &1.template.name)}}
    end
  end

  defp day(nil), do: {:ok, Date.utc_today()}

  defp day(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, day} -> {:ok, day}
      _invalid -> {:error, {:invalid_params, %{day: "must be YYYY-MM-DD"}}}
    end
  end

  defp day(_value), do: {:error, {:invalid_params, %{day: "must be YYYY-MM-DD"}}}

  @doc "One requirement with its content and version history."
  @spec get(binary(), binary(), binary()) :: {:ok, map()} | {:error, :requirement_not_found}
  def get(organization_id, mission_id, requirement_id) do
    case ContactRequirements.fetch(organization_id, mission_id, requirement_id) do
      {:ok, requirement, version} ->
        names = names(organization_id, mission_id, [version.spacecraft_id])

        versions =
          organization_id
          |> ContactRequirements.list_versions(mission_id, requirement_id)
          |> Enum.map(&%{version: &1.version, created_at: &1.created_at, actor: actor(&1)})

        {:ok, requirement |> row(version, names) |> Map.put(:versions, versions)}

      {:error, _not_found} ->
        {:error, :requirement_not_found}
    end
  end

  @doc "Creates (`requirement_id` nil) or versions a requirement: `{:ok, %{id, version}}`."
  @spec save(Scope.t(), binary(), binary() | nil | {:new, binary()}, map()) ::
          {:ok, map()} | {:error, term()}
  def save(%Scope{} = scope, mission_id, nil, %{"operation_id" => op} = params) when op != nil do
    PlanningOperations.create_once(scope, mission_id, :requirement, op, fn id ->
      save(scope, mission_id, {:new, id}, Map.delete(params, "operation_id"))
    end)
  end

  def save(%Scope{} = scope, mission_id, requirement_id, params) do
    with {:ok, content} <- Schema.admit(params["content"]),
         {:ok, requirement, version} <- write(scope, mission_id, requirement_id, content, params) do
      {:ok, %{id: requirement.contact_requirement_id, version: version.version}}
    else
      {:error, :stale_contact_requirement_version} ->
        {:error, {:version_conflict, current_version(scope, mission_id, requirement_id)}}

      {:error, :contact_requirement_not_active} ->
        {:error, {:requirement_not_active, ended(scope, mission_id, requirement_id)}}

      {:error, reason} ->
        {:error, error(reason)}
    end
  end

  @doc """
  Closes (the need is over) or cancels (withdrawn) a requirement at `expected_version`, with a
  required `reason`. Both are final: `{:ok, %{id, state, version}}`.
  """
  @spec end_requirement(Scope.t(), binary(), binary(), :close | :cancel, map()) ::
          {:ok, map()} | {:error, term()}
  def end_requirement(%Scope{} = scope, mission_id, requirement_id, action, params)
      when action in [:close, :cancel] do
    with {:ok, expected} <- expected_version(params["expected_version"]),
         {:ok, reason} <- reason(params["reason"]),
         {:ok, requirement} <-
           apply(ContactRequirements, action, [
             scope,
             mission_id,
             requirement_id,
             expected,
             reason
           ]) do
      {:ok,
       %{
         id: requirement.contact_requirement_id,
         state: requirement.lifecycle_state,
         version: requirement.current_version
       }}
    else
      {:error, :stale_contact_requirement_version} ->
        {:error, {:version_conflict, current_version(scope, mission_id, requirement_id)}}

      {:error, :contact_requirement_not_active} ->
        {:error, {:requirement_not_active, ended(scope, mission_id, requirement_id)}}

      {:error, reason} ->
        {:error, error(reason)}
    end
  end

  defp expected_version(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp expected_version(_n),
    do: {:error, {:invalid_params, %{expected_version: "is required (positive integer)"}}}

  defp reason(reason) when is_binary(reason) do
    trimmed = String.trim(reason)

    cond do
      trimmed == "" ->
        reason(nil)

      String.length(trimmed) > @max_reason ->
        {:error, {:invalid_params, %{reason: "must be at most #{@max_reason} characters"}}}

      true ->
        {:ok, trimmed}
    end
  end

  defp reason(_reason), do: {:error, {:invalid_params, %{reason: "is required"}}}

  # fe-setup: "Already closed by Mira K." without a refetch.
  defp ended(scope, mission_id, requirement_id) do
    case ContactRequirements.fetch(scope.organization_id, mission_id, requirement_id) do
      {:ok, requirement, _version} ->
        %{state: requirement.lifecycle_state, state_changed: state_changed(requirement)}

      {:error, _reason} ->
        %{}
    end
  end

  defp current_version(scope, mission_id, requirement_id) do
    case ContactRequirements.fetch(scope.organization_id, mission_id, requirement_id) do
      {:ok, requirement, _version} -> requirement.current_version
      {:error, _reason} -> nil
    end
  end

  # On create, omitted fields take the schema's defaults (`schema/0`'s `defaults`).
  defp write(scope, mission_id, nil, content, _params),
    do: ContactRequirements.create(scope, mission_id, Map.merge(Schema.defaults(), content))

  defp write(scope, mission_id, {:new, id}, content, _params) do
    attrs = Schema.defaults() |> Map.merge(content) |> Map.put(:contact_requirement_id, id)
    ContactRequirements.create(scope, mission_id, attrs)
  end

  defp write(scope, mission_id, requirement_id, content, params) do
    with {:ok, expected} <- expected_version(params["expected_version"]) do
      ContactRequirements.version(scope, mission_id, requirement_id, expected, content)
    end
  end

  defp row(requirement, version, names) do
    %{
      id: requirement.contact_requirement_id,
      state: requirement.lifecycle_state,
      version: version.version,
      spacecraft: %{id: version.spacecraft_id, name: Map.get(names, version.spacecraft_id)},
      template_id: RequirementListing.template_id(version),
      template_version: RequirementListing.template_version(version),
      content: version |> Map.from_struct() |> Map.take(content_atoms()),
      rule_summary: rule_summary(version),
      updated_at: version.created_at,
      state_changed: state_changed(requirement)
    }
  end

  # The templates' sentence without a cadence, plus the gap limit: "1 downlink ≥ 5 min each ·
  # gaps ≤ 6h00".
  defp rule_summary(version) do
    asks =
      TemplateDescriptions.requirement_summary(%{
        "contact_count" => version.contact_count,
        "service_direction" => to_string(version.service_direction),
        "success_measure" => to_string(version.success_measure),
        "minimum_duration_seconds" => version.minimum_duration_seconds,
        "minimum_data_volume_bytes" => version.minimum_data_volume_bytes
      })

    case Map.get(version, :max_gap_seconds) do
      gap when is_integer(gap) -> asks <> " · gaps ≤ " <> TemplateDescriptions.duration(gap)
      _none -> asks
    end
  end

  defp state_changed(%{lifecycle_state: :active}), do: nil

  defp state_changed(requirement) do
    %{
      at: requirement.lifecycle_changed_at,
      by:
        actor(%{
          organization_id: requirement.organization_id,
          created_by: requirement.lifecycle_changed_by
        }),
      reason: requirement.lifecycle_reason
    }
  end

  # The version struct's own keys whose names are the content keys (no atom creation).
  defp content_atoms do
    keys = Schema.content_keys()
    for field <- Map.keys(%ContactRequirementVersion{}), Atom.to_string(field) in keys, do: field
  end

  defp filters(params) do
    with {:ok, state} <- choice(params["state"], @states, :state),
         {:ok, source} <- choice(params["source"], @sources, :source),
         {:ok, page} <- positive(params["page"], 1, nil, :page),
         {:ok, limit} <- positive(params["limit"], @default_limit, @max_limit, :limit) do
      {:ok,
       %{
         spacecraft_id: blank(params["spacecraft_id"]),
         state: state,
         source: source,
         page: page,
         limit: limit
       }}
    end
  end

  # String → atom only through the explicit maps above.
  defp choice(nil, _allowed, _key), do: {:ok, nil}

  defp choice(value, allowed, key) do
    case Map.fetch(allowed, value) do
      {:ok, atom} ->
        {:ok, atom}

      :error ->
        {:error,
         {:invalid_params,
          %{key => "must be one of #{allowed |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"}}}
    end
  end

  defp positive(nil, default, _max, _key), do: {:ok, default}

  defp positive(value, default, max, key) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> positive(n, default, max, key)
      _other -> positive(:invalid, default, max, key)
    end
  end

  defp positive(n, _default, max, _key)
       when is_integer(n) and n > 0 and (is_nil(max) or n <= max),
       do: {:ok, n}

  defp positive(_value, _default, max, key),
    do:
      {:error, {:invalid_params, %{key => "must be a positive integer#{max && " up to #{max}"}"}}}

  defp blank(""), do: nil
  defp blank(value), do: value

  defp names(organization_id, mission_id, ids) do
    case SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, Enum.uniq(ids)) do
      {:ok, found} -> Map.new(found, fn {id, craft} -> {id, craft.display_name} end)
      {:error, _reason} -> %{}
    end
  end

  # user, service or system (drift sweep: the console has no "actor" kind).
  defp actor(%{created_by: id} = version) when is_binary(id),
    do: ActorRef.resolve(Map.get(version, :organization_id), id)

  defp actor(_version), do: nil

  # Domain errors → console problems. Field validation becomes 422 details keyed by field.
  defp error({:invalid_params, _details} = invalid), do: invalid

  defp error({:invalid_contact_requirement, message}),
    do: {:invalid_params, %{field_of(message) => message}}

  defp error({:contact_requirement_field_invalid, field, message}),
    do: {:invalid_params, %{to_string(field) => message}}

  defp error({:contact_requirement_field_too_large, field, maximum}),
    do: {:invalid_params, %{to_string(field) => "must be at most #{maximum} characters"}}

  defp error(:contact_requirement_document_too_large),
    do: {:invalid_params, %{content: "is too large"}}

  defp error(:invalid_contact_requirement_constraints),
    do: {:invalid_params, %{constraints: "allowed and excluded must be lists of ids"}}

  defp error(:conflicting_contact_requirement_constraints),
    do: {:invalid_params, %{constraints: "an id can't be both allowed and excluded"}}

  defp error(:contact_requirement_spacecraft_not_found),
    do: {:invalid_params, %{spacecraft_id: "unknown spacecraft"}}

  defp error(:contact_requirement_not_found), do: :requirement_not_found

  defp error(:contact_requirement_transition_reason_required),
    do: {:invalid_params, %{reason: "is required"}}

  defp error(%Ecto.Changeset{errors: errors}),
    do: {:invalid_params, Map.new(errors, fn {field, {message, _opts}} -> {field, message} end)}

  defp error(reason), do: reason

  # The domain's messages name the field first ("latest_end must be after earliest_start",
  # "unsupported success_measure: …").
  defp field_of(message) do
    words = message |> String.split([" ", ":"], trim: true) |> Enum.take(2)
    Enum.find(words, "content", &(&1 in Schema.content_keys()))
  end
end
