defmodule Cadence.Reads.ApplicationSurfaces.MissionCatalog do
  @moduledoc "Core-owned trusted read models for the Mission Catalog application."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{
    ActionConfirmation,
    HostContext,
    LifecycleActions,
    SurfaceQueryRequest
  }

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.ExtensionCatalog
  alias Cadence.Ids
  alias Cadence.Missions
  alias Cadence.Reads.Applications.Inventory
  alias Cadence.Reads.Applications.InventoryItem
  alias Cadence.SpacecraftStore

  @application_key "mission_catalog"
  @application_version 1
  @surface_version 1
  @max_param_keys 16

  @detail_params %{
    "catalog_database_show" => "catalog_database_id",
    "catalog_revision_show" => "catalog_revision_id",
    "catalog_artifact_show" => "artifact_id",
    "catalog_import_run_show" => "import_run_id"
  }

  @impl true
  def application_key, do: @application_key

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host_context, %SurfaceQueryRequest{} = request) do
    guarded(fn -> load_surface(scope, host_context, request) end)
  end

  defp load_surface(
         %Scope{organization_id: organization_id} = scope,
         %HostContext{} = host_context,
         %SurfaceQueryRequest{
           application_key: @application_key,
           application_version: @application_version,
           surface_version: @surface_version,
           query_version: @surface_version,
           surface_id: surface_id,
           query_id: query_id,
           params: params
         }
       )
       when is_binary(organization_id) and organization_id != "" and is_map(params) do
    with :ok <- authorize_scope(scope, host_context),
         :ok <- validate_query_identity(surface_id, query_id),
         :ok <- validate_params(surface_id, params),
         {:ok, data} <- dispatch_surface(scope, host_context, surface_id, params),
         {:ok, safe_data} <- JSONBoundary.safe(data) do
      {:ok,
       %{
         "navigation" => navigation(host_context, surface_id, params),
         "data" => safe_data
       }}
    end
  end

  defp load_surface(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp authorize_scope(
         %Scope{} = scope,
         %HostContext{placement: :organization, organization_id: organization_id}
       )
       when is_binary(organization_id) do
    Policy.authorize(scope, :operate_organization, %{organization_id: organization_id})
  end

  defp authorize_scope(
         %Scope{} = scope,
         %HostContext{placement: :mission, mission_id: mission_id}
       )
       when is_binary(mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize_scope(_scope, _host_context),
    do: {:error, :unsupported_application_host_context}

  defp validate_query_identity(surface_id, query_id) do
    if is_binary(surface_id) and query_id == "cadence.mission_catalog." <> surface_id,
      do: :ok,
      else: {:error, :unsupported_application_surface_query}
  end

  defp validate_params(surface_id, params) do
    keys = Map.keys(params)

    cond do
      length(keys) > @max_param_keys -> {:error, :application_surface_bounds_exceeded}
      not Enum.all?(keys, &is_binary/1) -> {:error, :invalid_application_request}
      surface_id in Map.keys(@detail_params) -> validate_detail_params(surface_id, params)
      params == %{} -> :ok
      true -> {:error, :invalid_application_request}
    end
  end

  defp validate_detail_params(surface_id, params) do
    required = Map.fetch!(@detail_params, surface_id)

    if MapSet.new(Map.keys(params)) == MapSet.new([required]) do
      subject_id(params, required)
      |> case do
        {:ok, _id} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_application_request}
    end
  end

  defp subject_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case Ids.path_segment(value) do
          {:ok, value} -> {:ok, value}
          {:error, :invalid_identifier} -> {:error, :invalid_application_request}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp dispatch_surface(scope, %HostContext{placement: :organization}, "mission_list", _params),
    do: mission_list(scope.organization_id)

  defp dispatch_surface(_scope, %HostContext{placement: :organization}, "mission_new", _params),
    do: {:ok, mission_new_data()}

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "mission_overview",
         _params
       ),
       do: mission_overview(scope.organization_id, mission_id)

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "mission_applications",
         _params
       ),
       do: mission_applications(scope, mission_id)

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "catalog_index",
         _params
       ),
       do: catalog_index(scope.organization_id, mission_id)

  defp dispatch_surface(
         _scope,
         %HostContext{placement: :mission},
         "catalog_database_new",
         _params
       ),
       do: {:ok, catalog_database_new_data()}

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "catalog_database_show",
         params
       ),
       do: catalog_database_show(scope.organization_id, mission_id, params)

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "catalog_revision_show",
         params
       ),
       do: catalog_revision_show(scope.organization_id, mission_id, params)

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "catalog_artifact_show",
         params
       ),
       do: catalog_artifact_show(scope.organization_id, mission_id, params)

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "catalog_import_run_show",
         params
       ),
       do: catalog_import_run_show(scope.organization_id, mission_id, params)

  defp dispatch_surface(_scope, _host_context, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp mission_list(organization_id) do
    rows =
      organization_id
      |> Missions.list_missions()
      |> Enum.map(fn mission ->
        spacecraft = SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)
        ready? = spacecraft != [] and Enum.all?(spacecraft, &is_integer(&1.scid))

        %{
          "id" => "mission-row-#{mission.mission_id}",
          "display_name" => mission.display_name,
          "slug" => mission.slug,
          "spacecraft_count" => length(spacecraft),
          "status" =>
            if(spacecraft == [], do: "info", else: if(ready?, do: "ready", else: "attention")),
          "status_label" =>
            cond do
              spacecraft == [] -> "No spacecraft"
              ready? -> "Ready"
              true -> "Needs setup"
            end,
          "href" => mission_href(mission.mission_id)
        }
      end)

    {:ok,
     %{
       "presentation" => %{
         "root_class" => "space-y-6",
         "header" => %{
           "class" => "border-b border-primary/20 pb-4",
           "content_class" => "flex items-end justify-between gap-4",
           "eyebrow" => %{"class" => "hud-label", "text" => "Organization"},
           "title" => %{
             "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight",
             "text" => "Missions",
             "suffix" => %{
               "class" => "ml-3 font-mono text-base text-base-content/60",
               "text" => "#{length(rows)} configured"
             }
           },
           "actions_class" => "flex items-center gap-2",
           "action" => %{
             "attrs" => navigate_attrs("/missions/new"),
             "class" => "btn btn-primary btn-sm gap-1",
             "icon_class" => "hero-plus h-4 w-4",
             "label" => "New Mission"
           }
         },
         "empty_state" => %{
           "visible" => rows == [],
           "id" => "mission-list-empty-state",
           "class" =>
             "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
           "icon_class" => "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block",
           "title" => %{"class" => "hud-label mt-3", "text" => "No missions yet"},
           "description" => %{
             "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70",
             "text" => "Create your first mission to get started."
           },
           "action_container_class" => "mt-5",
           "action" => %{
             "attrs" => navigate_attrs("/missions/new"),
             "class" => "btn btn-primary btn-sm gap-1",
             "icon_class" => "hero-plus h-4 w-4",
             "label" => "Create Mission"
           }
         },
         "card" => %{
           "visible" => rows != [],
           "class" => "card bg-base-200 border border-base-300",
           "body_class" => "card-body p-0",
           "rows" => rows
         }
       }
     }}
  end

  defp mission_new_data do
    %{
      "page" => %{
        "id" => "mission-new-page",
        "heading" => "New Mission",
        "breadcrumbs" => [
          %{"label" => "Missions", "href" => "/missions"},
          %{"label" => "New", "href" => nil}
        ]
      },
      "form" => %{
        "id" => "mission-form",
        "fields" => %{
          "display_name" =>
            mission_field("mission_display_name", "mission[display_name]", "Display Name"),
          "slug" => mission_field("mission_slug", "mission[slug]", "Slug")
        },
        "actions" => %{
          "submit" => %{"id" => "create-mission-button", "label" => "Create Mission"},
          "cancel" => %{"id" => "cancel-mission-link", "label" => "Cancel", "href" => "/missions"}
        }
      }
    }
  end

  defp mission_field(id, name, label),
    do: %{
      "id" => id,
      "name" => name,
      "type" => "text",
      "label" => label,
      "required" => true,
      "value" => ""
    }

  defp mission_overview(organization_id, mission_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id) do
      spacecraft = SpacecraftStore.list_spacecraft(organization_id, mission_id)
      endpoints = Cadence.SourceEndpoints.list_source_endpoints(organization_id, mission_id)
      templates = Cadence.Contacts.list_path_templates(organization_id, mission_id)
      assignments = Cadence.Contacts.list_link_assignments(organization_id, mission_id)

      readiness =
        Enum.map(spacecraft, &readiness_row(&1, endpoints, templates, assignments, mission_id))

      ready = Enum.count(readiness, &(&1["status"] == "ready"))
      missing_scid = Enum.count(readiness, &is_nil(&1["scid"]))
      missing_path = Enum.count(readiness, &(&1["status"] == "attention"))
      issues = Enum.count(readiness, &(&1["status"] != "ready"))

      {:ok,
       %{
         "overview" => %{
           "mission" => %{
             "eyebrow" => "Mission",
             "display_name" => mission.display_name,
             "slug" => mission.slug
           },
           "readiness_cards" => [
             readiness_card(
               "Ready Spacecraft",
               ready,
               if(ready == 0, do: "attention", else: "ready"),
               "Spacecraft with SCID and identity configured."
             ),
             readiness_card(
               "Need SCID",
               missing_scid,
               if(missing_scid == 0, do: "ready", else: "blocked"),
               "Spacecraft that cannot be resolved from incoming frames yet."
             ),
             readiness_card(
               "Need Link",
               missing_path,
               if(missing_path == 0, do: "ready", else: "attention"),
               "Spacecraft with identity configured but no provider link."
             )
           ],
           "setup" => %{
             "eyebrow" => "Spacecraft Readiness",
             "title" => "Configure spacecraft identity and select a spacecraft profile",
             "description" =>
               "Each row shows whether a spacecraft can be identified from incoming frames and has a profile that defines its byte-interpretation contract.",
             "issue_count" => issues,
             "status" => status_dto(if(issues == 0, do: "ready", else: "attention")),
             "empty" => readiness == [],
             "empty_state" => %{
               "title" => "No spacecraft have been registered for this mission yet.",
               "action_label" => "Add the first spacecraft",
               "action_href" => "/missions/#{mission_id}/spacecraft/new"
             }
           }
         },
         "spacecraft_readiness" => readiness
       }}
    end
  end

  defp readiness_card(title, value, tone, description),
    do: %{
      "title" => title,
      "value" => value,
      "status" => status_dto(tone),
      "description" => description
    }

  defp readiness_row(spacecraft, endpoints, templates, assignments, mission_id) do
    endpoint = Enum.find(endpoints, &(&1.spacecraft_id == spacecraft.spacecraft_id))
    endpoint_id = endpoint && endpoint.source_endpoint_id
    assigned = Enum.filter(assignments, &(&1.source_endpoint_ref == endpoint_id))

    available =
      Enum.count(
        templates,
        &(&1.direction == :downlink and is_nil(&1.source_endpoint_ref) and
            &1.provider_profile_refs != [])
      )

    provider_paths =
      Enum.count(assigned, &(&1.direction == :downlink and &1.provider_profile_refs != []))

    status =
      cond do
        is_nil(spacecraft.scid) -> "blocked"
        is_nil(endpoint) -> "blocked"
        provider_paths > 0 -> "ready"
        true -> "attention"
      end

    issue =
      cond do
        is_nil(spacecraft.scid) ->
          "Set SCID so Cadence can identify this spacecraft from TM transfer frames."

        is_nil(endpoint) ->
          "Sync the internal telemetry identity for this spacecraft."

        available > 0 ->
          "Assign an available downlink route to this spacecraft."

        true ->
          "Create a provider-backed downlink routing rule for this spacecraft."
      end

    path_label =
      cond do
        is_nil(endpoint) ->
          "No downlink route"

        provider_paths > 0 ->
          "#{provider_paths} downlink route#{if(provider_paths == 1, do: "", else: "s")}"

        available > 0 ->
          "Available to assign"

        true ->
          "No downlink route"
      end

    %{
      "id" => spacecraft.spacecraft_id,
      "actions_id" => "#{spacecraft.spacecraft_id}-readiness-actions",
      "spacecraft_display_name" => spacecraft.display_name,
      "spacecraft_id" => spacecraft.spacecraft_id,
      "scid_label" =>
        if(is_nil(spacecraft.scid), do: "Not set", else: Integer.to_string(spacecraft.scid)),
      "endpoint_label" => if(is_nil(endpoint), do: "Missing", else: "Telemetry identity"),
      "endpoint_ref_label" => endpoint_id || "Not created",
      "path_label" => path_label,
      "path_detail" =>
        if(provider_paths > 0,
          do: "#{provider_paths} provider-backed",
          else:
            if(available > 0,
              do:
                "#{available} available mission template#{if(available == 1, do: "", else: "s")}",
              else: "Not configured"
            )
        ),
      "status" => status,
      "status_label" =>
        %{"ready" => "Ready", "attention" => "Needs link", "blocked" => "Needs identity"}[status],
      "issue" => issue,
      "primary_action" =>
        %{
          "ready" => "Review readiness",
          "attention" => "Assign link",
          "blocked" => if(is_nil(spacecraft.scid), do: "Set SCID", else: "Sync identity")
        }[status],
      "primary_action_href" =>
        "/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness",
      "view_spacecraft_href" => "/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
    }
  end

  defp mission_applications(scope, mission_id) do
    host_context = HostContext.mission(mission_id)

    with {:ok, applications} <-
           Inventory.catalog(
             scope,
             host_context,
             ExtensionCatalog.available_applications_for_scope(:mission)
           ) do
      {:ok,
       %{
         "presentation" => %{
           "root" => %{"attrs" => %{"id" => "mission-applications-page", "class" => "space-y-6"}},
           "header" => %{
             "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
             "body" => %{"attrs" => %{}},
             "content" => %{"attrs" => %{}},
             "breadcrumbs" => mission_breadcrumbs("Applications", mission_id),
             "title" => %{
               "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
               "text" => "Applications"
             },
             "subtitle" => %{
               "attrs" => %{"class" => "mt-1 max-w-3xl text-sm text-base-content/70"},
               "text" =>
                 "Install mission-scoped product capabilities and open their host-rendered workspaces."
             }
           },
           "applications_component" => %{
             "attrs" => %{"id" => "mission-applications-component"},
             "props" => %{
               "applications" => Enum.map(applications, &application_row(&1, mission_id))
             }
           }
         }
       }}
    end
  end

  defp application_row(%InventoryItem{} = application, mission_id) do
    card_id = "mission-application-#{safe_key(application.application_key)}"

    %{
      "id" => card_id,
      "application_key" => application.application_key,
      "application_version" => application.application_version,
      "display_name" => application.display_name,
      "description" => application.description,
      "lifecycle_state" => atom_string(application.lifecycle_state),
      "installable" => application.installable?,
      "manageable" => application.manageable?,
      "uninstallable" => application.uninstallable?,
      "scope_label" => "Mission Application",
      "manage_path" => "/missions/#{mission_id}/applications/#{application.application_key}",
      "status" => status_dto(application.status),
      "install_action" =>
        if(application.installable? and not application.manageable?,
          do: lifecycle_action("install", application.lifecycle_state, card_id)
        ),
      "disable_action" =>
        if(application.manageable?,
          do: lifecycle_action("disable", application.lifecycle_state, card_id)
        ),
      "uninstall_action" =>
        if(application.uninstallable?,
          do: lifecycle_action("uninstall", application.lifecycle_state, card_id)
        ),
      "unavailable_message" =>
        if(application.installable?,
          do: nil,
          else: "This application is not available for installation in this deployment."
        )
    }
  end

  defp status_dto(status) when is_binary(status),
    do: %{"tone" => status, "label" => status_label(status)}

  defp status_dto(status) do
    %{
      "state" => atom_string(status.state),
      "label" => status.label,
      "tone" => atom_string(status.tone),
      "facts" =>
        Enum.map(status.facts, &%{"id" => &1.id, "label" => &1.label, "value" => &1.value})
    }
  end

  defp status_label("ready"), do: "Ready"
  defp status_label("attention"), do: "Needs Work"
  defp status_label("blocked"), do: "Missing"
  defp status_label(other), do: String.capitalize(other)

  defp lifecycle_action(action_id, state, card_id) do
    {:ok, action} = LifecycleActions.fetch(action_id)
    confirmation = action.confirmation

    %{
      "id" => "#{action_id}-#{card_id}",
      "action_id" => action.action_id,
      "label" => if(action_id == "install", do: install_label(state), else: action.label),
      "variant" => atom_string(action.button_variant),
      "effect" => atom_string(action.effect),
      "execution" => atom_string(action.execution),
      "confirmation" => confirmation && confirmation_dto(confirmation)
    }
  end

  defp confirmation_dto(%ActionConfirmation{} = confirmation),
    do: %{
      "title" => confirmation.title,
      "message" => confirmation.message,
      "confirm_label" => confirmation.confirm_label,
      "tone" => atom_string(confirmation.tone),
      "prompt" => ActionConfirmation.prompt(confirmation)
    }

  defp install_label(:disabled), do: "Enable"
  defp install_label(:uninstalled), do: "Reinstall"
  defp install_label(:installed), do: "Upgrade"
  defp install_label(_state), do: "Install"

  defp catalog_index(organization_id, mission_id) do
    databases = Catalog.list_databases(organization_id, mission_id)
    revisions = Catalog.latest_revision_by_database(organization_id, mission_id)
    runs = Catalog.latest_import_run_by_database(organization_id, mission_id)

    rows =
      Enum.map(databases, fn database ->
        revision = Map.get(revisions, database.catalog_database_id)
        run = Map.get(runs, database.catalog_database_id)

        %{
          "id" => "catalog-database-row-#{database.catalog_database_id}",
          "actions_id" => "#{database.catalog_database_id}-actions",
          "name" => database.name,
          "slug" => database.slug,
          "href" => "/missions/#{mission_id}/catalog/databases/#{database.catalog_database_id}",
          "latest_revision" =>
            revision &&
              %{
                "label" => revision.revision_label,
                "href" =>
                  "/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
              },
          "latest_import" =>
            run &&
              %{
                "status" => import_status_tone(run.status),
                "status_label" => import_status_label(run.status),
                "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
              }
        }
      end)

    {:ok,
     %{
       "presentation" => %{
         "root" => %{"attrs" => %{"class" => "space-y-6"}},
         "header" => catalog_header(mission_id),
         "empty_state" => %{
           "visible" => rows == [],
           "list" => %{"attrs" => %{"id" => "catalog-database-list"}},
           "root" => %{
             "attrs" => %{
               "class" =>
                 "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
             }
           },
           "title" => %{
             "attrs" => %{"class" => "hud-label"},
             "text" => "No catalog databases yet"
           },
           "description" => %{
             "attrs" => %{"class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"},
             "text" => "Use + New database above to import the first revision."
           }
         },
         "card" => %{
           "visible" => rows != [],
           "root" => %{
             "attrs" => %{
               "class" => "card bg-base-200 border border-base-300",
               "id" => "catalog-database-list"
             }
           },
           "body" => %{"attrs" => %{"class" => "card-body p-0"}},
           "child_wrapper" => %{"attrs" => %{"id" => "catalog-databases-table-component"}},
           "rows" => rows
         }
       }
     }}
  end

  defp catalog_database_new_data do
    %{
      "page" => %{
        "id" => "catalog-database-new-page",
        "heading" => "New catalog database",
        "breadcrumbs" => [
          %{"label" => "Mission", "href" => nil},
          %{"label" => "Catalog", "href" => nil},
          %{"label" => "New database", "href" => nil}
        ],
        "cancel" => %{
          "id" => "catalog-database-new-cancel",
          "label" => "Cancel",
          "href" => "/catalog"
        }
      },
      "form" =>
        upload_form(
          "catalog-upload-form",
          "catalog_database",
          "Create catalog database revision",
          "Upload & import",
          nil
        ),
      "upload" => upload_config("artifact"),
      "detected_importer" => %{"status" => "empty", "display_name" => nil},
      "submit_disabled" => true
    }
  end

  defp catalog_database_show(organization_id, mission_id, params) do
    with {:ok, database_id} <- subject_id(params, "catalog_database_id"),
         {:ok, database} <- Catalog.fetch_database(organization_id, mission_id, database_id) do
      revisions = Catalog.list_revisions(organization_id, mission_id, database_id)

      runs =
        Catalog.list_import_runs(organization_id, mission_id, catalog_database_id: database_id)

      {:ok,
       %{
         "database" => %{
           "id" => database.catalog_database_id,
           "name" => database.name,
           "slug" => database.slug,
           "description" =>
             database.description ||
               "Mission catalog library entry. Add immutable revisions here, then choose runtime usage separately.",
           "runtime_usage_summary" => "No runtime bindings yet."
         },
         "navigation" => %{
           "mission" => %{"label" => "Mission", "href" => mission_href(mission_id)},
           "catalog" => %{"label" => "Catalog", "href" => "/missions/#{mission_id}/catalog"},
           "current" => %{"label" => database.name}
         },
         "revision_form_open" => false,
         "revision_form" =>
           upload_form(
             "catalog-revision-upload-form",
             "catalog_revision",
             "Add revision",
             "Upload revision",
             "catalog-revision-upload-card"
           ),
         "upload" => upload_config("artifact"),
         "detected_importer" => %{"status" => "empty", "display_name" => nil},
         "submit_disabled" => true,
         "revisions" => Enum.map(revisions, &revision_row(&1, mission_id)),
         "import_runs" => Enum.map(runs, &import_run_row(&1, mission_id))
       }}
    end
  end

  defp catalog_revision_show(organization_id, mission_id, params) do
    with {:ok, revision_id} <- subject_id(params, "catalog_revision_id"),
         {:ok, revision} <- Catalog.fetch_revision(organization_id, mission_id, revision_id) do
      database =
        optional(fn ->
          Catalog.fetch_database(organization_id, mission_id, revision.catalog_database_id)
        end)

      artifact =
        optional(fn ->
          Catalog.fetch_artifact(organization_id, mission_id, revision.artifact_id)
        end)

      run =
        optional(fn ->
          Catalog.fetch_import_run(organization_id, mission_id, revision.import_run_id)
        end)

      model =
        optional(fn ->
          Cadence.MissionModels.fetch_revision(
            organization_id,
            mission_id,
            revision.mission_model_revision_id
          )
        end)

      plans =
        optional(fn ->
          Cadence.MissionModels.fetch_runtime_plans(
            organization_id,
            mission_id,
            revision.mission_model_revision_id
          )
        end) || %{}

      navigation =
        [
          %{"label" => "Mission", "href" => mission_href(mission_id)},
          %{"label" => "Catalog", "href" => "/missions/#{mission_id}/catalog"}
        ] ++
          if(database,
            do: [
              %{
                "label" => database.name,
                "href" =>
                  "/missions/#{mission_id}/catalog/databases/#{database.catalog_database_id}"
              }
            ],
            else: []
          ) ++ [%{"label" => revision.revision_label, "href" => nil}]

      {:ok,
       %{
         "revision" => %{
           "title" => revision.revision_label,
           "number_label" => "Revision #{revision.revision_number}"
         },
         "navigation" => %{"breadcrumbs" => navigation},
         "provenance" => %{
           "id" => "catalog-revision-provenance",
           "title" => "Revision provenance",
           "rows" => [
             %{
               "label" => "Database",
               "value" => database && database.name,
               "href" => nil,
               "style" => "default"
             },
             %{
               "label" => "Artifact",
               "value" => artifact && artifact.artifact_name,
               "href" =>
                 artifact && "/missions/#{mission_id}/catalog/artifacts/#{artifact.artifact_id}",
               "style" => "default"
             },
             %{
               "label" => "Import run",
               "value" => run && run.import_run_id,
               "href" => run && "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}",
               "style" => "mono"
             },
             %{
               "label" => "Content SHA-256",
               "value" => revision.content_sha256,
               "href" => nil,
               "style" => "hash"
             }
           ]
         },
         "runtime_usage" => %{
           "id" => "catalog-revision-runtime-usage",
           "title" => "Runtime usage",
           "summary_id" => "catalog-runtime-usage-summary",
           "summary" => "No runtime bindings yet.",
           "action" => %{
             "id" => "catalog-revision-runtime-action",
             "label" => "Use this revision in runtime",
             "disabled" => true
           }
         },
         "mission_model" => mission_model_dto(model, plans)
       }}
    end
  end

  defp catalog_artifact_show(organization_id, mission_id, params) do
    with {:ok, artifact_id} <- subject_id(params, "artifact_id"),
         {:ok, artifact} <- Catalog.fetch_artifact(organization_id, mission_id, artifact_id) do
      runs = Catalog.list_import_runs(organization_id, mission_id, artifact_id: artifact_id)

      {:ok,
       %{
         "presentation" => %{
           "root" => %{"attrs" => %{"id" => "catalog-artifact-show-page", "class" => "space-y-6"}},
           "header" => artifact_header(mission_id, artifact),
           "child_wrapper" => %{"attrs" => %{"id" => "catalog-artifact-show-component"}},
           "artifact_show" => %{
             "artifact" => %{
               "format_key" => artifact.format_key,
               "media_type" => artifact.media_type || "—",
               "content_sha256" => artifact.content_sha256,
               "uploaded_at" => format_datetime(artifact.uploaded_at),
               "download_href" =>
                 "/missions/#{mission_id}/catalog/artifacts/#{artifact.artifact_id}/download"
             },
             "runs" => Enum.map(runs, &artifact_run_row(&1, mission_id))
           }
         }
       }}
    end
  end

  defp catalog_import_run_show(organization_id, mission_id, params) do
    with {:ok, run_id} <- subject_id(params, "import_run_id"),
         {:ok, run} <- Catalog.fetch_import_run(organization_id, mission_id, run_id) do
      summary = Map.get(run.result_document || %{}, "mission_model")

      {:ok,
       %{
         "navigation" => %{
           "breadcrumbs" => [
             %{"label" => "Mission", "href" => mission_href(mission_id)},
             %{"label" => "Catalog", "href" => "/missions/#{mission_id}/catalog"},
             %{
               "label" => "Artifact",
               "href" => "/missions/#{mission_id}/catalog/artifacts/#{run.artifact_id}"
             },
             %{"label" => "Import run", "href" => nil}
           ]
         },
         "status" => %{
           "label" => import_status_label(run.status),
           "tone" => import_status_tone(run.status)
         },
         "run_details" => %{
           "importer" => %{
             "id" => "catalog-importer-version",
             "label" => "#{run.importer_key} v#{run.importer_version}"
           },
           "started_at" => format_datetime(run.started_at),
           "completed_at" => format_datetime(run.completed_at)
         },
         "mission_model" => mission_model_run(summary),
         "diagnostic_groups" => diagnostic_groups(run.diagnostics),
         "failure_reason" => failure_reason(run)
       }}
    end
  end

  defp mission_model_dto(nil, _plans),
    do: %{
      "id" => "catalog-mission-model",
      "title" => "Mission Model",
      "available" => false,
      "empty_message" => "Mission Model unavailable.",
      "rows" => []
    }

  defp mission_model_dto(model, plans),
    do: %{
      "id" => "catalog-mission-model",
      "title" => "Mission Model",
      "available" => true,
      "empty_message" => "Mission Model unavailable.",
      "rows" => [
        %{"label" => "Revision", "value" => model.revision_id, "href" => nil, "style" => "hash"},
        %{
          "label" => "Declarations",
          "value" => map_size(model.declarations),
          "href" => nil,
          "style" => "default"
        },
        %{
          "label" => "Space systems",
          "value" => map_size(model.space_systems),
          "href" => nil,
          "style" => "default"
        },
        %{
          "label" => "Ready plans",
          "value" => Enum.count(plans, fn {_target, plan} -> plan.status == :ready end),
          "href" => nil,
          "style" => "default"
        }
      ]
    }

  defp mission_model_run(nil), do: nil

  defp mission_model_run(summary) when is_map(summary),
    do: %{
      "id" => "catalog-import-mission-model",
      "revision_id" => Map.get(summary, "revision_id"),
      "declaration_count" => Map.get(summary, "declaration_count"),
      "plan_count" => map_size(Map.get(summary, "plans") || %{})
    }

  defp diagnostic_groups(diagnostics) do
    [:error, :warning, :info]
    |> Enum.flat_map(fn severity ->
      items = Enum.filter(diagnostics || [], &(Map.get(&1, :severity) == severity))

      if items == [],
        do: [],
        else: [
          %{
            "title" => "#{severity_label(severity)} (#{length(items)})",
            "items" => Enum.map(items, &diagnostic_row/1)
          }
        ]
    end)
  end

  defp severity_label(:error), do: "Errors"
  defp severity_label(:warning), do: "Warnings"
  defp severity_label(:info), do: "Info"

  defp diagnostic_row(diagnostic) do
    metadata = Map.get(diagnostic, :metadata, %{}) || %{}

    detail =
      [
        metadata_value(metadata, "consumption_summary", "Built-in telemetry"),
        metadata_value(metadata, "consumption_status", "Status"),
        metadata_value(metadata, "packet_name", "Packet"),
        metadata_value(metadata, "entry_name", "Entry"),
        metadata_value(metadata, "point_name", "Point"),
        metadata_value(metadata, "type_name", "Type"),
        metadata_value(metadata, "base_type", "Base type"),
        metadata_value(metadata, "point_id", "Point ID"),
        metadata_value(metadata, "type_id", "Type ID")
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        values -> Enum.join(values, " | ")
      end

    %{
      "code" => diagnostic.code,
      "message" => diagnostic.message,
      "detail" => detail,
      "path" => if(diagnostic.path == [], do: nil, else: Enum.join(diagnostic.path, " / "))
    }
  end

  defp metadata_value(metadata, key, label) do
    case Map.get(metadata, key) do
      value when is_binary(value) and value != "" -> "#{label}: #{value}"
      _ -> nil
    end
  end

  defp failure_reason(%{status: :failed, failure_reason: {:exception, message}})
       when is_binary(message), do: message

  defp failure_reason(%{status: :failed, failure_reason: {kind, reason}}) when is_atom(kind),
    do: "#{kind}: #{inspect(reason)}"

  defp failure_reason(%{status: :failed, failure_reason: reason}) when not is_nil(reason),
    do: inspect(reason)

  defp failure_reason(_run), do: nil

  defp revision_row(revision, mission_id),
    do: %{
      "id" => "catalog-revision-row-#{revision.catalog_revision_id}",
      "revision_id" => revision.catalog_revision_id,
      "label" => revision.revision_label,
      "number" => revision.revision_number,
      "mission_model_revision_id" => revision.mission_model_revision_id,
      "href" => "/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
    }

  defp import_run_row(run, mission_id),
    do: %{
      "id" => "catalog-import-run-row-#{run.import_run_id}",
      "run_id" => run.import_run_id,
      "status" => %{
        "value" => atom_string(run.status),
        "label" => import_status_label(run.status),
        "tone" => import_status_tone(run.status)
      },
      "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }

  defp artifact_run_row(run, mission_id),
    do: %{
      "id" => "catalog-artifact-run-#{run.import_run_id}",
      "actions_id" => "#{run.import_run_id}-actions",
      "status" => import_status_tone(run.status),
      "status_label" => import_status_label(run.status),
      "started_at" => format_short_datetime(run.started_at),
      "completed_at" => format_short_datetime(run.completed_at) || "—",
      "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }

  defp import_status_tone(:completed), do: "ready"
  defp import_status_tone(:failed), do: "blocked"
  defp import_status_tone(_status), do: "info"
  defp import_status_label(:running), do: "Running"
  defp import_status_label(:completed), do: "Completed"
  defp import_status_label(:failed), do: "Failed"
  defp import_status_label(status), do: status |> to_string() |> String.capitalize()

  defp upload_form(id, name, title, submit_label, card_id) do
    %{
      "id" => id,
      "name" => name,
      "class" => "space-y-4",
      "card" => %{
        "id" => card_id,
        "class" => "card bg-base-200 border border-base-300",
        "body_class" => "card-body p-6",
        "title" => title,
        "title_class" => "hud-label"
      },
      "content_class" => if(name == "catalog_database", do: "space-y-4 mt-2", else: nil),
      "description" =>
        if(name == "catalog_database",
          do: %{
            "text" =>
              "Save the upload as an immutable revision in the mission catalog library. Runtime usage is chosen separately.",
            "class" => "text-sm text-base-content/70"
          },
          else: nil
        ),
      "primary_fields_class" => "grid grid-cols-1 md:grid-cols-2 gap-4",
      "primary_fields" => upload_fields(name),
      "secondary_fields" =>
        if(name == "catalog_database",
          do: [upload_field(name, "revision_notes", "textarea", "Revision notes")],
          else: []
        ),
      "file_input" => %{
        "id" =>
          if(name == "catalog_database",
            do: "catalog-upload-file-input",
            else: "catalog-revision-upload-file-input"
          ),
        "name" => "artifact",
        "class" => "file-input file-input-bordered w-full",
        "wrapper_class" => if(name == "catalog_database", do: "block", else: nil)
      },
      "entries" => upload_entries(),
      "error_class" => "border px-4 py-3 text-sm text-base-content border-error/40 bg-error/10",
      "importer" => importer_presentation(),
      "actions_class" => if(name == "catalog_database", do: "flex items-center gap-3", else: nil),
      "submit" => %{
        "id" => if(name == "catalog_database", do: nil, else: "catalog-revision-upload-submit"),
        "label" => submit_label,
        "class" => "btn btn-primary"
      }
    }
  end

  defp upload_fields(name),
    do: [
      upload_field(
        name,
        "#{if(name == "catalog_database", do: "name", else: "revision_label")}",
        "text",
        if(name == "catalog_database", do: "Catalog database name", else: "Revision label")
      ),
      upload_field(
        name,
        if(name == "catalog_database", do: "revision_label", else: "revision_notes"),
        "text",
        if(name == "catalog_database", do: "Revision label", else: "Notes")
      )
    ]

  defp upload_field(form_name, key, type, label),
    do: %{
      "key" => key,
      "id" => "#{form_name}_#{key}",
      "name" => "#{form_name}[#{key}]",
      "type" => type,
      "label" => label,
      "value" => "",
      "errors" => [],
      "wrapper_class" => "fieldset mb-3",
      "label_class" => "hud-label block mb-1.5",
      "input_class" => if(type == "textarea", do: "w-full textarea", else: "w-full input"),
      "error_class" => "mt-1.5 text-sm text-error"
    }

  defp upload_entries,
    do: %{
      "list_class" => "space-y-1",
      "item_class" => "flex items-center justify-between text-sm",
      "name_class" => "font-mono",
      "progress_class" => "progress progress-primary h-1 w-24",
      "remove_class" => "btn btn-ghost btn-xs",
      "remove_label" => "Remove"
    }

  defp importer_presentation,
    do: %{
      "detected_class" => "flex items-center gap-2 text-sm text-base-content/80",
      "icon_class" => "hero-check-circle h-4 w-4 text-success",
      "name_class" => "font-medium",
      "empty_class" => "text-xs text-base-content/60"
    }

  defp upload_config(ref),
    do: %{
      "ref" => ref,
      "name" => "artifact",
      "accept" => false,
      "max_entries" => 1,
      "max_file_size" => 52_428_800,
      "auto_upload" => false,
      "entries" => [],
      "errors" => []
    }

  defp catalog_header(mission_id),
    do: %{
      "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
      "body" => %{"attrs" => %{"class" => "flex items-end justify-between gap-4"}},
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => mission_breadcrumbs("Catalog", mission_id),
      "title" => %{
        "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
        "text" => "Catalog"
      },
      "subtitle" => %{
        "attrs" => %{"class" => "mt-1 max-w-3xl text-sm text-base-content/70"},
        "text" =>
          "Mission database library. Revisions are imported here; runtime usage is selected later."
      },
      "actions" => %{"attrs" => %{"class" => "flex items-center gap-2"}},
      "new_database" => %{
        "attrs" =>
          Map.merge(navigate_attrs("/missions/#{mission_id}/catalog/new"), %{
            "id" => "new-database-link"
          }),
        "icon" => %{"attrs" => %{"class" => "hero-plus h-4 w-4"}},
        "text" => "New database"
      }
    }

  defp artifact_header(mission_id, artifact),
    do: %{
      "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
      "body" => %{"attrs" => %{}},
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => %{
        "attrs" => %{
          "aria-label" => "Breadcrumb",
          "class" =>
            "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        },
        "items" => [
          %{
            "key" => "mission",
            "separator" => nil,
            "link" => %{"attrs" => navigate_attrs(mission_href(mission_id)), "text" => "Mission"},
            "current" => nil
          },
          %{
            "key" => "catalog",
            "separator" => separator(),
            "link" => %{
              "attrs" => navigate_attrs("/missions/#{mission_id}/catalog"),
              "text" => "Catalog"
            },
            "current" => nil
          },
          %{
            "key" => "artifact",
            "separator" => separator(),
            "link" => nil,
            "current" => %{
              "attrs" => %{"class" => "text-primary/90"},
              "text" => artifact.artifact_name
            }
          }
        ]
      },
      "title" => %{
        "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
        "text" => artifact.artifact_name
      }
    }

  defp mission_breadcrumbs(current, mission_id),
    do: %{
      "attrs" => %{
        "aria-label" => "Breadcrumb",
        "class" =>
          "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
      },
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{"attrs" => navigate_attrs(mission_href(mission_id)), "text" => "Mission"},
          "current" => nil
        },
        %{
          "key" => "current",
          "separator" => separator(),
          "link" => nil,
          "current" => %{"attrs" => %{"class" => "text-primary/90"}, "text" => current}
        }
      ]
    }

  defp separator,
    do: %{"attrs" => %{"class" => "text-base-content/20", "aria-hidden" => "true"}, "text" => "/"}

  defp navigate_attrs(href),
    do: %{"data-phx-link" => "redirect", "data-phx-link-state" => "push", "href" => href}

  defp navigation(%HostContext{placement: :organization}, _surface_id, _params),
    do: %{"fallback_href" => "/missions"}

  defp navigation(%HostContext{mission_id: mission_id}, surface_id, params),
    do: %{
      "fallback_href" => "/missions/#{mission_id}",
      "surface_id" => surface_id,
      "params" => params
    }

  defp mission_href(mission_id), do: "/missions/#{mission_id}"
  defp safe_key(key), do: String.replace(key, ~r/[^A-Za-z0-9_-]+/, "-")
  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value
  defp format_datetime(nil), do: nil
  defp format_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  defp format_short_datetime(nil), do: nil
  defp format_short_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S")

  defp optional(fun) do
    case fun.() do
      {:ok, value} -> value
      {:error, _} -> nil
    end
  end

  defp guarded(fun) do
    case fun.() do
      {:ok, _result} = result -> result
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_application_surface_provider_registry}
    end
  rescue
    _exception -> {:error, :invalid_application_surface_provider_registry}
  catch
    _kind, _value -> {:error, :invalid_application_surface_provider_registry}
  end
end
