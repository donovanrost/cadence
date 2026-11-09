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

  alias Cadence.Accounts
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirementTemplates,
    ContactRequirementTemplateVersion,
    TemplateDescriptions,
    TemplateTargets
  }

  alias Cadence.Control.PlanningPolicy
  alias Cadence.{SpacecraftStore, SpacecraftTypeStore}

  @day 86_400

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

        versions =
          organization_id
          |> ContactRequirementTemplates.list_versions(mission_id, template_id)
          |> Enum.map(
            &%{version: &1.version, created_at: &1.created_at, actor: actor(&1.created_by)}
          )

        {:ok,
         template
         |> row(version, names)
         |> Map.merge(%{document: document(version), versions: versions})}

      {:error, _missing} ->
        {:error, :template_not_found}
    end
  end

  @doc """
  Creates (`template_id` nil) or versions a template from wire params
  `%{"name", "document", "target", "expected_version"}`.
  """
  @spec save(Scope.t(), binary(), binary() | nil, map()) ::
          {:ok, %{id: binary(), version: pos_integer()}} | {:error, term()}
  def save(scope, mission_id, template_id, params) do
    scope
    |> write(mission_id, template_id, params)
    |> target_error(params)
  end

  defp write(%Scope{} = scope, mission_id, nil, params) do
    with {:ok, _template, version} <-
           ContactRequirementTemplates.create(scope, mission_id, attrs(params)) do
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

    occurrences =
      version
      |> ContactRequirementTemplates.preview_occurrences(from, until)
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

  defp actor(user_id) do
    name =
      case Accounts.fetch_user(user_id) do
        {:ok, user} -> user.display_name || user.email
        _missing -> nil
      end

    %{kind: "user", id: user_id, name: name}
  end

  defp expected_version(n) when is_integer(n) and n > 0, do: {:ok, n}
  defp expected_version(_n), do: {:error, {:invalid_params, %{expected_version: "is required"}}}
end
