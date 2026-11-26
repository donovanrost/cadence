defmodule Cadence.Control.PlanningTemplates do
  @moduledoc """
  Console CP1/CP3: targeted contact requirement templates (DECISIONS #37,
  docs/apogee/domain/contact-templates.md) as the Setup screen reads and edits
  them, plus the planning summary.

  The wire `target` is the version's `target_document` (`TemplateTargets`);
  the wire `document` is `%{schedule, requirement, catch_up_policy}`. Writes
  go through `ContactRequirementTemplates` (organization admins), which
  validates and versions them; templates aren't change sets (planning policy,
  not mission configuration).
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirementTemplates,
    ContactRequirementTemplateVersion,
    RequirementSchedule,
    TemplateDescriptions,
    TemplateTargets
  }

  alias Cadence.Control.{PlanningOperations, PlanningPolicy}
  alias Cadence.{SpacecraftStore, SpacecraftTypeStore}

  @day 86_400
  # 31 days at the 60 s minimum interval.
  @max_preview_occurrences 44_640

  @doc "Templates that aren't closed, each with its target and rule in words."
  @spec list(binary(), binary()) :: [map()]
  def list(organization_id, mission_id) do
    names = names(organization_id, mission_id)

    organization_id
    |> ContactRequirementTemplates.list(mission_id)
    |> Enum.reject(fn {template, _version} -> template.lifecycle_state == :closed end)
    |> Enum.map(fn {template, version} -> row(template, version, names) end)
  end

  @spec get(binary(), binary(), binary()) :: {:ok, map()} | {:error, :template_not_found}
  def get(organization_id, mission_id, template_id) do
    case ContactRequirementTemplates.fetch(organization_id, mission_id, template_id) do
      {:ok, template, version} ->
        names = names(organization_id, mission_id)

        listed =
          ContactRequirementTemplates.list_versions(organization_id, mission_id, template_id)

        people = MemberNames.members(organization_id, actor_ids(template, listed))

        {:ok,
         template
         |> row(version, names)
         |> Map.merge(%{
           document: document(version),
           versions: Enum.map(listed, &version_row(&1, people)),
           state_changed: state_changed(template, people)
         })}

      {:error, _missing} ->
        {:error, :template_not_found}
    end
  end

  @doc """
  Pauses, resumes (`:activate`) or closes a template (§11 L2) at `params["expected_version"]`,
  with a required `params["reason"]`. A lifecycle move doesn't bump the version; requirements the
  template already made stay. `{:ok, %{id, state, version}}`.
  """
  @spec transition(Scope.t(), binary(), binary(), :pause | :activate | :close, map()) ::
          {:ok, map()} | {:error, term()}
  def transition(%Scope{} = scope, mission_id, template_id, action, params)
      when action in [:pause, :activate, :close] do
    with {:ok, expected} <- expected_version(params["expected_version"]),
         {:ok, reason} <- reason(params["reason"]),
         {:ok, template} <-
           apply(ContactRequirementTemplates, action, [
             scope,
             mission_id,
             template_id,
             expected,
             reason
           ]) do
      {:ok,
       %{
         id: template.contact_requirement_template_id,
         state: template.lifecycle_state,
         version: template.current_version
       }}
    else
      {:error, :stale_contact_requirement_template_version} ->
        {:error, {:version_conflict, current(scope, mission_id, template_id, :current_version)}}

      {:error, :invalid_template_lifecycle_transition} ->
        {:error,
         {:template_transition_not_allowed,
          current(scope, mission_id, template_id, :lifecycle_state)}}

      {:error, :contact_requirement_template_transition_reason_required} ->
        {:error, {:invalid_params, %{reason: "Say why."}}}

      other ->
        other
    end
  end

  defp current(scope, mission_id, template_id, field) do
    case ContactRequirementTemplates.fetch(scope.organization_id, mission_id, template_id) do
      {:ok, template, _version} -> Map.get(template, field)
      _missing -> nil
    end
  end

  defp reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" ->
        reason(nil)

      trimmed ->
        if String.length(trimmed) <= 2_000,
          do: {:ok, trimmed},
          else: {:error, {:invalid_params, %{reason: "must be at most 2000 characters"}}}
    end
  end

  defp reason(_reason), do: {:error, {:invalid_params, %{reason: "Say why."}}}

  # The last lifecycle move a person made; creating and versioning record system reasons.
  defp state_changed(%{lifecycle_reason: r}, _) when r in [nil, "created", "versioned"], do: nil

  defp state_changed(template, people) do
    %{
      state: template.lifecycle_state,
      at: template.lifecycle_changed_at,
      actor: template.lifecycle_changed_by && actor(template.lifecycle_changed_by, people),
      reason: template.lifecycle_reason
    }
  end

  @doc """
  Creates (`template_id` nil) or versions a template from wire params
  `%{"name", "document", "target", "expected_version"}`.
  """
  @spec save(Scope.t(), binary(), binary() | nil | {:new, binary()}, map()) ::
          {:ok, %{id: binary(), version: pos_integer()}} | {:error, term()}
  def save(scope, mission_id, nil, %{"operation_id" => op} = params) when op != nil do
    PlanningOperations.create_once(scope, mission_id, :template, op, fn id ->
      save(scope, mission_id, {:new, id}, Map.delete(params, "operation_id"))
    end)
  end

  def save(scope, mission_id, template_id, params) do
    scope
    |> write(mission_id, template_id, params)
    |> target_error(params)
  end

  defp write(%Scope{} = scope, mission_id, nil, params),
    do: write(scope, mission_id, {:new, nil}, params)

  # `id` is the operation's derived id (PlanningOperations), else the store mints one.
  defp write(%Scope{} = scope, mission_id, {:new, id}, params) do
    attrs =
      if id, do: Map.put(attrs(params), :contact_requirement_template_id, id), else: attrs(params)

    with {:ok, _template, version} <- ContactRequirementTemplates.create(scope, mission_id, attrs) do
      {:ok, %{id: version.contact_requirement_template_id, version: version.version}}
    end
  end

  defp write(%Scope{} = scope, mission_id, template_id, params) do
    with {:ok, expected} <- expected_version(params["expected_version"]),
         {:ok, _template, version} <-
           ContactRequirementTemplates.version(
             scope,
             mission_id,
             template_id,
             expected,
             attrs(params)
           ) do
      {:ok, %{id: template_id, version: version.version}}
    end
  end

  # A one-spacecraft list reports the legacy error; name the ids like any other target.
  defp target_error({:error, :contact_requirement_template_spacecraft_not_found}, params),
    do:
      {:error,
       {:template_target_unknown_spacecraft, get_in(params, ["target", "spacecraft_ids"]) || []}}

  # A requirement field the template carries (#74's max_gap_seconds, say) names its form path.
  defp target_error({:error, {:contact_requirement_field_invalid, field, message}}, _params),
    do: {:error, {:invalid_params, %{"requirement.#{field}" => message}}}

  defp target_error(result, _params), do: result

  @doc """
  What a template would do over `[from, until)`, writing nothing:
  `{spacecraft_count, occurrences, contacts, contacts_per_day, warnings}`.
  Warnings: `applies_to_nobody`, `excluded_outside_target` (with ids).
  """
  @spec preview(Scope.t(), binary(), map(), DateTime.t(), DateTime.t()) ::
          {:ok, map()} | {:error, term()}
  def preview(%Scope{organization_id: organization_id}, mission_id, params, from, until) do
    with {:ok, version} <- draft_version(organization_id, mission_id, params),
         :ok <- TemplateTargets.validate(organization_id, mission_id, version.target_document) do
      {:ok, effect(organization_id, mission_id, version, from, until)}
    end
  end

  @doc "CP1: policy, coverage, templates, what isn't covered, and permissions."
  @spec summary(Scope.t(), binary()) :: map()
  def summary(%Scope{organization_id: organization_id} = scope, mission_id) do
    from = DateTime.utc_now() |> DateTime.truncate(:second)
    until = DateTime.add(from, @day, :second)
    spacecraft = SpacecraftStore.list_spacecraft(organization_id, mission_id)

    templates =
      ContactRequirementTemplates.list(organization_id, mission_id, lifecycle_state: :active)

    effects =
      Enum.map(templates, fn {_template, version} ->
        effect(organization_id, mission_id, version, from, until)
      end)

    covered = effects |> Enum.flat_map(& &1.spacecraft_ids) |> MapSet.new()

    %{
      policy: policy(organization_id, mission_id),
      coverage: %{
        spacecraft_total: length(spacecraft),
        covered: MapSet.size(covered),
        contacts_per_day: effects |> Enum.map(& &1.contacts) |> Enum.sum(),
        uplink_passes_per_day:
          templates
          |> Enum.zip(effects)
          |> Enum.filter(fn {{_, v}, _} ->
            v.requirement_document["service_direction"] in ["uplink", "bidirectional"]
          end)
          |> Enum.map(fn {_, effect} -> effect.contacts end)
          |> Enum.sum()
      },
      templates: list(organization_id, mission_id),
      not_covered: not_covered(organization_id, mission_id, spacecraft, covered),
      permissions: PlanningPolicy.permissions(scope)
    }
  end

  defp effect(organization_id, mission_id, version, from, until) do
    target = version.target_document
    candidates = TemplateTargets.candidates(organization_id, mission_id, target)
    ids = TemplateTargets.select(target, candidates)

    # The whole window, not the catch-up bounds (lookback, occurrences per run) that limit
    # one materialization.
    occurrences =
      version.schedule_document
      |> RequirementSchedule.occurrences_between(from, until, @max_preview_occurrences)
      |> Enum.count(&DateTime.before?(&1, until))

    contacts = occurrences * length(ids) * (version.requirement_document["contact_count"] || 1)
    days = max(DateTime.diff(until, from), 1) / @day
    outside = TemplateTargets.excluded_outside(target, candidates)

    %{
      spacecraft_count: length(ids),
      spacecraft_ids: ids,
      occurrences: occurrences,
      contacts: contacts,
      contacts_per_day: Float.round(contacts / days, 1),
      warnings:
        Enum.reject(
          [
            if(ids == [], do: %{code: "applies_to_nobody"}),
            if(outside != [], do: %{code: "excluded_outside_target", spacecraft_ids: outside})
          ],
          &is_nil/1
        )
    }
  end

  defp row(template, %ContactRequirementTemplateVersion{} = version, names) do
    %{
      id: template.contact_requirement_template_id,
      name: version.name,
      state: template.lifecycle_state,
      version: version.version,
      target: version.target_document,
      applies_to: TemplateDescriptions.applies_to(version.target_document, names),
      applies_to_count:
        length(
          TemplateTargets.resolve(
            version.organization_id,
            version.mission_id,
            version.target_document
          )
        ),
      rule_summary: TemplateDescriptions.rule_summary(version),
      priority: version.requirement_document["priority"]
    }
  end

  defp document(version) do
    %{
      schedule: version.schedule_document,
      requirement: version.requirement_document,
      catch_up_policy: version.catch_up_policy_document
    }
  end

  defp attrs(params) do
    document = params["document"] || %{}

    [
      {:name, params["name"]},
      {:target_document, params["target"]},
      {:schedule_document, document["schedule"]},
      {:requirement_document, document["requirement"]},
      {:catch_up_policy_document, document["catch_up_policy"]}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp draft_version(organization_id, mission_id, params) do
    {:ok,
     params
     |> attrs()
     |> Map.merge(%{
       contact_requirement_template_id: "template_preview",
       organization_id: organization_id,
       mission_id: mission_id,
       created_by: "preview"
     })
     |> ContactRequirementTemplateVersion.new()}
  rescue
    error in ArgumentError -> {:error, {:invalid_contact_requirement_template, error.message}}
  end

  defp not_covered(organization_id, mission_id, spacecraft, covered) do
    profiles =
      organization_id
      |> SpacecraftTypeStore.list_spacecraft_types(mission_id)
      |> Map.new(&{&1.spacecraft_type_id, &1.display_name})

    spacecraft
    |> Enum.reject(&MapSet.member?(covered, &1.spacecraft_id))
    |> Enum.group_by(& &1.spacecraft_type_id)
    |> Enum.map(fn
      {nil, crafts} ->
        %{group: "none", label: "No profile", count: length(crafts), suggested_target: nil}

      {profile_id, crafts} ->
        %{
          group: "profile",
          label: Map.get(profiles, profile_id, profile_id),
          count: length(crafts),
          suggested_target: %{"kind" => "profile", "spacecraft_type_id" => profile_id}
        }
    end)
    |> Enum.sort_by(&(-&1.count))
  end

  defp policy(organization_id, mission_id) do
    case PlanningPolicy.get(organization_id, mission_id) do
      %{active_version: nil} ->
        nil

      %{active_version: active, document: document} ->
        %{version: active, mode: get_in(document || %{}, ["automation", "mode"])}
    end
  end

  defp names(organization_id, mission_id) do
    crafts =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Map.new(&{&1.spacecraft_id, &1.display_name})

    organization_id
    |> SpacecraftTypeStore.list_spacecraft_types(mission_id)
    |> Map.new(&{&1.spacecraft_type_id, &1.display_name})
    |> Map.merge(crafts)
  end

  defp version_row(v, people),
    do: %{version: v.version, created_at: v.created_at, actor: actor(v.created_by, people)}

  defp actor_ids(template, versions),
    do: Enum.filter([template.lifecycle_changed_by | Enum.map(versions, & &1.created_by)], & &1)

  # #146 (#468): only an active member is named and keeps their id; never an email.
  defp actor(id, p) when is_map_key(p, id), do: %{kind: "user", id: id, name: p[id]}
  defp actor(_id, _people), do: %{kind: "user", id: nil, name: nil}

  defp expected_version(n) when is_integer(n) and n > 0, do: {:ok, n}
  defp expected_version(_n), do: {:error, {:invalid_params, %{expected_version: "is required"}}}
end
