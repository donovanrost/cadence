defmodule Cadence.Reads.Comms.MissionProviders do
  @moduledoc "Authorized mission-provider read models independent of frontend delivery."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.GroundNetworks.{
    DeliveryProfile,
    ProviderAccountGrants,
    ProviderAccounts,
    ServiceProfile
  }

  alias Cadence.Ids
  alias Cadence.Management.Providers
  alias Cadence.Missions
  alias Cadence.Platform.RedactedJson
  @max_map_keys 64
  @pages ~w(provider_list provider_new provider_show)

  def load(scope, mission_id, page, params \\ %{})

  def load(%Scope{organization_id: org, mission_id: scoped} = scope, mission_id, page, params)
      when page in @pages and is_binary(org) and org != "" and is_binary(mission_id) and
             mission_id != "" and is_map(params) and (is_nil(scoped) or scoped == mission_id) do
    guarded(fn ->
      with :ok <- validate_params(page, params),
           :ok <- authorize(scope, mission_id),
           {:ok, mission} <- Missions.fetch_mission(org, mission_id),
           :ok <- ensure_mission_scope(mission, org, mission_id),
           :ok <- validate_mission_param(params, mission_id),
           :ok <- validate_identifiers([mission_id]) do
        dispatch_surface(scope, mission, page, params)
      end
    end)
  end

  def load(_scope, _mission_id, _page, _params),
    do: {:error, :unsupported_application_surface_query}

  defp dispatch_surface(_scope, mission, "provider_list", _params) do
    providers = Providers.list_providers(mission.organization_id, mission.mission_id)
    rows = Enum.map(providers, &provider_table_row(&1, mission.mission_id))

    data = %{
      "presentation" => provider_list_presentation(mission, length(providers), rows)
    }

    trusted_payload("provider_list", mission.mission_id, nil, data)
  end

  defp dispatch_surface(_scope, mission, "provider_new", params) do
    bindings = granted_bindings(mission.organization_id, mission.mission_id)
    default_grant_id = bindings |> List.first() |> binding_value(:grant_id, "")

    case selected_binding(bindings, params, default_grant_id) do
      {:ok, selected_binding} ->
        provider_new_payload(mission, bindings, selected_binding, default_grant_id)

      {:error, :invalid_application_request} = error ->
        if bindings == [] and not provider_binding_requested?(params),
          do: provider_new_payload(mission, bindings, nil, default_grant_id),
          else: error
    end
  end

  defp dispatch_surface(_scope, mission, "provider_show", params) do
    with {:ok, provider_id} <- subject_id(params, "provider_id"),
         {:ok, provider} <-
           Providers.fetch_provider(mission.organization_id, mission.mission_id, provider_id) do
      versions =
        Providers.list_provider_versions(
          mission.organization_id,
          mission.mission_id,
          provider_id
        )

      service_profiles =
        provider |> profile_items("service_profiles") |> Enum.map(&service_profile_dto/1)

      delivery_profiles =
        provider |> profile_items("delivery_profiles") |> Enum.map(&delivery_profile_dto/1)

      data = %{
        "navigation" => provider_navigation(mission, provider),
        "provider" => provider_dto(provider, length(service_profiles), length(delivery_profiles)),
        "actions" => provider_actions(provider),
        "profiles" => profiles_dto(service_profiles == [], delivery_profiles == []),
        "details" => provider_details(provider),
        "diagnostics" => provider_diagnostics(provider),
        "service_profiles" => service_profiles,
        "delivery_profiles" => delivery_profiles,
        "provider_versions" => Enum.map(versions, &provider_version_dto/1)
      }

      trusted_payload("provider_show", mission.mission_id, provider_id, data)
    else
      {:error, :mission_provider_not_found} ->
        {:error, :unsupported_application_surface_query}

      error ->
        error
    end
  end

  defp dispatch_surface(_scope, _mission, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp provider_new_payload(mission, bindings, selected_binding, default_grant_id) do
    form_params = default_params(binding_value(selected_binding, :grant_id, default_grant_id))

    data = %{
      "page" => provider_new_page(mission),
      "accounts" => accounts_dto(bindings, selected_binding),
      "notes" => notes_dto(),
      "form" => provider_form_dto(form_params, mission, bindings)
    }

    trusted_payload("provider_new", mission.mission_id, nil, data)
  end

  defp provider_binding_requested?(params) do
    is_binary(params["provider_account_id"]) or
      is_binary(params["provider_account_grant_id"])
  end

  defp validate_params("provider_show", params) do
    validate_param_keys(params, MapSet.new(["mission_id", "provider_id"]))
  end

  defp validate_params("provider_new", params) do
    validate_param_keys(
      params,
      MapSet.new(["mission_id", "provider_account_grant_id", "provider_account_id"])
    )
  end

  defp validate_params("provider_list", params),
    do: validate_param_keys(params, MapSet.new(["mission_id"]))

  defp validate_params(_surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp validate_param_keys(params, allowed_keys) do
    keys = Map.keys(params)

    cond do
      length(keys) > @max_map_keys -> {:error, :application_surface_bounds_exceeded}
      not Enum.all?(keys, &is_binary/1) -> {:error, :invalid_application_request}
      MapSet.subset?(MapSet.new(keys), allowed_keys) -> :ok
      true -> {:error, :invalid_application_request}
    end
  end

  defp validate_mission_param(params, mission_id) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      _other -> {:error, :invalid_application_request}
    end
  end

  defp authorize(%Scope{} = scope, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp ensure_mission_scope(
         %{organization_id: organization_id, mission_id: mission_id},
         organization_id,
         mission_id
       ),
       do: :ok

  defp ensure_mission_scope(_mission, _organization_id, _mission_id),
    do: {:error, :unsupported_application_surface_query}

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

  defp validate_identifiers(identifiers) do
    if Enum.all?(identifiers, &match?({:ok, _}, Ids.path_segment(&1))),
      do: :ok,
      else: {:error, :invalid_application_request}
  end

  defp trusted_payload(surface_id, mission_id, subject_id, data) do
    with {:ok, safe_data} <- bounded_json(data) do
      {:ok,
       %{
         "navigation" => navigation(surface_id, mission_id, subject_id),
         "data" => safe_data
       }}
    end
  end

  defp bounded_json(value) do
    case JSONBoundary.safe_trusted_output(value) do
      {:ok, safe} -> {:ok, safe}
      {:error, _reason} -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp navigation(surface_id, mission_id, subject_id) do
    %{
      "fallback_href" => fallback_href(mission_id, surface_id, subject_id),
      "breadcrumbs" => breadcrumbs(surface_id, mission_id, subject_id)
    }
  end

  defp breadcrumbs(surface_id, mission_id, subject_id) do
    items = [
      %{"label" => "Mission", "href" => "/missions/" <> segment!(mission_id)},
      %{"label" => "Comms", "href" => fallback_href(mission_id, "overview", nil)},
      %{
        "label" => surface_label(surface_id),
        "href" => fallback_href(mission_id, surface_id, subject_id)
      }
    ]

    if is_binary(subject_id),
      do: List.update_at(items, -1, &Map.put(&1, "href", nil)),
      else: items
  end

  defp provider_list_presentation(mission, provider_count, rows) do
    new_provider_path = mission_href(mission.mission_id, "/comms/providers/new")

    %{
      "root" => %{"attrs" => %{"id" => "comms-providers-page", "class" => "space-y-6"}},
      "header" => %{
        "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
        "body" => %{"attrs" => %{"class" => "flex items-end justify-between gap-4"}},
        "content" => %{"attrs" => %{}},
        "breadcrumbs" => provider_breadcrumbs(mission),
        "title" => %{
          "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
          "text" => "Ground Network Providers",
          "suffix" => %{
            "attrs" => %{"class" => "ml-3 font-mono text-base text-base-content/60"},
            "text" => "#{provider_count} configured"
          }
        },
        "subtitle" => %{
          "attrs" => %{"class" => "mt-1 max-w-3xl text-sm text-base-content/70"},
          "text" =>
            "Provider control planes for scheduling, inventory discovery, and delivery profile negotiation."
        },
        "actions" => %{
          "attrs" => %{"class" => "flex items-center gap-2"},
          "new_provider" => %{
            "attrs" =>
              navigate_attrs(new_provider_path, %{
                "id" => "new-provider-link",
                "class" => "btn btn-primary btn-sm gap-1"
              }),
            "icon" => %{"attrs" => %{"class" => "hero-plus h-4 w-4"}},
            "text" => "New Provider"
          }
        }
      },
      "empty_state" => empty_provider_state(provider_count == 0, new_provider_path),
      "card" => if(provider_count == 0, do: nil, else: provider_card(rows))
    }
  end

  defp provider_breadcrumbs(mission) do
    %{
      "attrs" => %{
        "aria-label" => "Breadcrumb",
        "class" =>
          "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
      },
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{
            "attrs" =>
              navigate_attrs(mission_href(mission.mission_id, ""), %{
                "class" => "hover:text-primary transition-colors"
              }),
            "text" => mission.display_name
          },
          "current" => nil
        },
        %{
          "key" => "comms",
          "separator" => breadcrumb_separator(),
          "link" => %{
            "attrs" =>
              navigate_attrs(mission_href(mission.mission_id, "/comms"), %{
                "class" => "hover:text-primary transition-colors"
              }),
            "text" => "Comms"
          },
          "current" => nil
        },
        %{
          "key" => "providers",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{"attrs" => %{"class" => "text-primary/90"}, "text" => "Providers"}
        }
      ]
    }
  end

  defp provider_card(rows) do
    %{
      "attrs" => %{"class" => "card bg-base-200 border border-base-300"},
      "body" => %{"attrs" => %{"class" => "card-body p-0"}},
      "table_component" => %{"attrs" => %{"id" => "mission-providers-table-component"}},
      "rows" => rows
    }
  end

  defp empty_provider_state(false, _new_provider_path), do: nil

  defp empty_provider_state(true, new_provider_path) do
    %{
      "attrs" => %{
        "class" =>
          "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
      },
      "title" => %{"attrs" => %{"class" => "hud-label"}, "text" => "No ground network providers"},
      "description" => %{
        "attrs" => %{"class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"},
        "text" =>
          "Connect this mission to a simulator or commercial ground network control plane."
      },
      "action_container" => %{"attrs" => %{"class" => "mt-5"}},
      "action" => %{
        "attrs" => navigate_attrs(new_provider_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{"attrs" => %{"class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"}},
        "text" => "Configure the first provider"
      }
    }
  end

  defp provider_table_row(provider, mission_id) do
    %{
      "id" => "mission-provider-#{provider.provider_id}",
      "display_name" => provider.display_name,
      "provider_type" => provider_type_label(provider),
      "server_url" => provider.base_url,
      "status" => Atom.to_string(control_plane_status(provider)),
      "status_label" => control_plane_label(provider),
      "account_binding" => account_binding_label(provider),
      "grant_binding" => grant_binding_label(provider),
      "last_synced_at" => timestamp_label(provider.last_synced_at),
      "version" => "v#{provider.version}",
      "href" => mission_href(mission_id, "/comms/providers/#{segment!(provider.provider_id)}")
    }
  end

  defp provider_new_page(mission) do
    %{
      "id" => "comms-provider-new-page",
      "title" => "New Mission Provider",
      "subtitle" =>
        "Bind an organization-approved ground network account and define this mission's delivery tolerances.",
      "breadcrumbs" => [
        %{"label" => mission.display_name, "href" => mission_href(mission.mission_id, "")},
        %{"label" => "Comms", "href" => mission_href(mission.mission_id, "/comms")},
        %{"label" => "Providers", "href" => mission_href(mission.mission_id, "/comms/providers")},
        %{"label" => "New", "href" => nil}
      ]
    }
  end

  defp accounts_dto(bindings, selected_binding) do
    %{
      "empty" => bindings == [],
      "options" => Enum.map(bindings, &binding_option_dto/1),
      "bindings" =>
        Enum.map(bindings, fn binding ->
          %{
            "grant_id" => binding.grant_id,
            "grant_version" => binding.grant.version,
            "account_id" => binding.account_version.provider_account_id,
            "account_version" => binding.account_version.version,
            "summary" => account_summary_dto(binding)
          }
        end),
      "selected" => account_summary_dto(selected_binding),
      "empty_state" => %{
        "id" => "mission-provider-no-grants",
        "heading" => "This mission has no Provider Account grants.",
        "message" =>
          "An organization administrator must grant an account before mission setup can continue.",
        "action" => %{
          "id" => "open-provider-accounts-link",
          "label" => "Open Provider Accounts",
          "href" => "/provider-accounts"
        }
      }
    }
  end

  defp account_summary_dto(nil), do: nil

  defp account_summary_dto(binding) do
    %{
      "id" => "mission-provider-account-summary",
      "ownership_label" => "Organization-owned configuration",
      "display_name" => binding.account.display_name,
      "version_label" =>
        "account v#{binding.account_version.version} · grant v#{binding.grant.version}",
      "badge" => %{"status" => "ready", "label" => "Granted"},
      "restrictions" => [
        %{
          "label" => "Account Guardrails",
          "summary" => restriction_summary(binding.account_version.guardrails)
        },
        %{
          "label" => "Mission Restrictions",
          "summary" => restriction_summary(binding.grant.restrictions)
        }
      ]
    }
  end

  defp notes_dto do
    %{
      "secret_boundary" => %{
        "id" => "mission-provider-secret-boundary-note",
        "text" =>
          "Provider endpoint, credential, and environment values remain organization-owned and are never exposed to this mission form."
      },
      "resource_boundary" => %{
        "id" => "mission-provider-resource-guardrail-note",
        "text" =>
          "Leave blank to inherit the grant. Any listed resources must be inside both the account guardrails and the mission grant."
      }
    }
  end

  defp provider_form_dto(params, mission, bindings) do
    policy_mode = string_param(params, "policy_mode")

    %{
      "id" => "mission-provider-form",
      "sections" => %{
        "binding" =>
          section_dto("mission-provider-binding-section", "01", "Mission Binding", [
            "display_name",
            "provider_account_grant_id"
          ]),
        "resource_scope" =>
          section_dto("mission-provider-resource-scope-section", "02", "Mission Resource Scope", [
            "permitted_resource_refs"
          ]),
        "delivery_policy" =>
          section_dto(
            "mission-provider-delivery-policy-section",
            "03",
            "Delivery Change Policy",
            ["policy_mode", "deadline_behavior"]
          )
      },
      "fields" => provider_fields_dto(params, bindings),
      "conditional" => %{
        "approval_guidance" => %{
          "id" => "mission-provider-approval-policy-guidance",
          "active" => policy_mode == "approval_required",
          "visible_when" => %{"field" => "policy_mode", "equals" => "approval_required"},
          "text" =>
            "Provider facts are still recorded immediately, but actionable schedule or resource changes wait for an authorized operator decision."
        },
        "bounded_policy" => %{
          "id" => "mission-provider-bounded-policy-fields",
          "active" => policy_mode == "bounded_automatic",
          "visible_when" => %{"field" => "policy_mode", "equals" => "bounded_automatic"},
          "field_keys" => [
            "maximum_earlier_start_shift_seconds",
            "maximum_later_start_shift_seconds",
            "maximum_earlier_end_shift_seconds",
            "maximum_later_end_shift_seconds",
            "minimum_retained_duration_seconds",
            "approved_station_substitutions"
          ]
        }
      },
      "actions" => %{
        "submit" => %{
          "id" => "create-mission-provider-button",
          "label" => "Create Mission Provider"
        },
        "cancel" => %{
          "id" => "cancel-mission-provider-link",
          "label" => "Cancel",
          "href" => mission_href(mission.mission_id, "/comms/providers")
        }
      }
    }
  end

  defp section_dto(id, number, title, field_keys),
    do: %{"id" => id, "number" => number, "title" => title, "field_keys" => field_keys}

  defp provider_fields_dto(params, bindings) do
    %{
      "display_name" => field_dto("display_name", "text", "Display Name", params, required: true),
      "provider_account_grant_id" =>
        field_dto("provider_account_grant_id", "select", "Granted Provider Account", params,
          required: true,
          options: Enum.map(bindings, &binding_option_dto/1)
        ),
      "permitted_resource_refs" =>
        field_dto(
          "permitted_resource_refs",
          "text",
          "Permitted Stations or Service Pools",
          params,
          placeholder: "station-alpha, station-beta"
        ),
      "policy_mode" =>
        field_dto("policy_mode", "select", "Material Change Handling", params,
          required: true,
          options: [
            option_dto("Require approval for every material change", "approval_required"),
            option_dto("Automatically accept changes within limits", "bounded_automatic")
          ]
        ),
      "maximum_earlier_start_shift_seconds" =>
        field_dto(
          "maximum_earlier_start_shift_seconds",
          "number",
          "Max Earlier Start Shift (seconds)",
          params,
          min: 0
        ),
      "maximum_later_start_shift_seconds" =>
        field_dto(
          "maximum_later_start_shift_seconds",
          "number",
          "Max Later Start Shift (seconds)",
          params,
          min: 0
        ),
      "maximum_earlier_end_shift_seconds" =>
        field_dto(
          "maximum_earlier_end_shift_seconds",
          "number",
          "Max Earlier End Shift (seconds)",
          params,
          min: 0
        ),
      "maximum_later_end_shift_seconds" =>
        field_dto(
          "maximum_later_end_shift_seconds",
          "number",
          "Max Later End Shift (seconds)",
          params,
          min: 0
        ),
      "minimum_retained_duration_seconds" =>
        field_dto(
          "minimum_retained_duration_seconds",
          "number",
          "Minimum Retained Duration (seconds)",
          params,
          min: 1
        ),
      "approved_station_substitutions" =>
        field_dto(
          "approved_station_substitutions",
          "text",
          "Approved Station Substitutions",
          params,
          placeholder: "station-alpha, station-beta"
        ),
      "deadline_behavior" =>
        field_dto("deadline_behavior", "select", "No-response Deadline Behavior", params,
          required: true,
          options: [
            option_dto("Retain last accepted schedule", "retain_last_accepted"),
            option_dto("Cancel if still actionable", "cancel_if_actionable")
          ]
        )
    }
  end

  defp field_dto(field, type, label, params, opts) do
    %{
      "key" => field,
      "id" => "provider_#{field}",
      "name" => "provider[#{field}]",
      "type" => type,
      "label" => label,
      "required" => Keyword.get(opts, :required, false),
      "placeholder" => Keyword.get(opts, :placeholder),
      "min" => Keyword.get(opts, :min),
      "options" => Keyword.get(opts, :options, []),
      "value" => string_param(params, field)
    }
  end

  defp binding_option_dto(binding),
    do:
      option_dto(
        "#{binding.account.display_name} · account v#{binding.account_version.version} · grant v#{binding.grant.version}",
        binding.grant_id
      )

  defp option_dto(label, value), do: %{"label" => label, "value" => value}

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp granted_bindings(organization_id, mission_id) do
    organization_id
    |> ProviderAccountGrants.list_for_mission(mission_id)
    |> Enum.flat_map(&granted_binding(organization_id, &1))
  end

  defp granted_binding(organization_id, grant) do
    with {:ok, account, _active_version} <-
           ProviderAccounts.fetch_for_system(organization_id, grant.provider_account_id),
         {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             organization_id,
             grant.provider_account_id,
             grant.provider_account_version
           ) do
      [
        %{
          grant_id: grant.provider_account_grant_id,
          grant: grant,
          account: account,
          account_version: account_version
        }
      ]
    else
      {:error, _reason} -> []
    end
  end

  defp default_params(grant_id) do
    %{
      "display_name" => "Ground Network Simulator",
      "provider_account_grant_id" => grant_id,
      "permitted_resource_refs" => "",
      "policy_mode" => "approval_required",
      "maximum_earlier_start_shift_seconds" => "0",
      "maximum_later_start_shift_seconds" => "0",
      "maximum_earlier_end_shift_seconds" => "0",
      "maximum_later_end_shift_seconds" => "0",
      "minimum_retained_duration_seconds" => "",
      "approved_station_substitutions" => "",
      "deadline_behavior" => "retain_last_accepted"
    }
  end

  defp selected_binding(bindings, params, default_grant_id) do
    selected =
      cond do
        is_binary(params["provider_account_id"]) ->
          Enum.find(
            bindings,
            &(&1.account_version.provider_account_id == params["provider_account_id"])
          )

        is_binary(params["provider_account_grant_id"]) ->
          Enum.find(bindings, &(&1.grant_id == params["provider_account_grant_id"]))

        true ->
          find_binding(bindings, default_grant_id)
      end

    if is_map(selected), do: {:ok, selected}, else: {:error, :invalid_application_request}
  end

  defp find_binding(bindings, grant_id), do: Enum.find(bindings, &(&1.grant_id == grant_id))

  defp binding_value(nil, _key, default), do: default
  defp binding_value(binding, key, _default), do: Map.fetch!(binding, key)

  defp restriction_summary(restrictions) when map_size(restrictions) == 0,
    do: "No additional limits"

  defp restriction_summary(restrictions) do
    Enum.map_join(restrictions, " · ", fn {key, value} ->
      "#{humanize(key)}: #{restriction_value(value)}"
    end)
  end

  defp restriction_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp restriction_value(value), do: to_string(value)

  defp provider_navigation(mission, provider) do
    %{
      "breadcrumbs" => [
        %{"label" => mission.display_name, "href" => mission_href(mission.mission_id, "")},
        %{"label" => "Comms", "href" => mission_href(mission.mission_id, "/comms")},
        %{"label" => "Providers", "href" => mission_href(mission.mission_id, "/comms/providers")},
        %{"label" => provider.display_name, "href" => nil}
      ]
    }
  end

  defp provider_dto(provider, service_profile_count, delivery_profile_count) do
    %{
      "page_id" => "comms-provider-show-page",
      "display_name" => provider.display_name,
      "provider_id" => provider.provider_id,
      "simulated_badge" => %{"id" => "simulated-provider-badge", "label" => "Simulated"},
      "version" => "v#{provider.version}",
      "summary_tiles" => [
        summary_tile(
          "provider-control-plane-health",
          "Control Plane",
          control_plane_label(provider)
        ),
        summary_tile("provider-last-sync", "Last Sync", timestamp_label(provider.last_synced_at)),
        summary_tile("provider-service-profile-count", "Service Profiles", service_profile_count),
        summary_tile(
          "provider-delivery-profile-count",
          "Delivery Profiles",
          delivery_profile_count
        )
      ]
    }
  end

  defp summary_tile(id, label, value), do: %{"id" => id, "label" => label, "value" => value}

  defp provider_actions(provider) do
    %{
      "validate" => %{
        "id" => "validate-provider-button",
        "label" => "Validate",
        "disabled" => provider.lifecycle_state != :active
      },
      "sync" => %{
        "id" => "sync-provider-button",
        "label" => "Sync Inventory",
        "disabled" => provider.lifecycle_state != :active
      },
      "archive" => %{
        "id" => "archive-provider-button",
        "label" => "Archive",
        "confirm" => "Archive this ground network provider?",
        "disabled" => provider.lifecycle_state != :active
      }
    }
  end

  defp profiles_dto(service_empty?, delivery_empty?) do
    %{
      "service" => %{
        "id" => "provider-service-profiles",
        "heading" => "Service Profiles",
        "subtitle" => "Provider-owned service definitions available to contact scheduling.",
        "empty" => service_empty?,
        "empty_copy" => "Sync provider inventory to discover service profiles.",
        "table_id" => "service-profiles-table",
        "table_body_id" => "service-profiles-table-body",
        "columns" => ["Service", "Kind", "Direction", "Data Families", "State"]
      },
      "delivery" => %{
        "id" => "provider-delivery-profiles",
        "heading" => "Delivery Profiles",
        "subtitle" =>
          "Provider delivery options; Cadence transports are resolved from these profiles later.",
        "empty" => delivery_empty?,
        "empty_copy" => "Sync provider inventory to discover delivery profiles.",
        "table_id" => "delivery-profiles-table",
        "table_body_id" => "delivery-profiles-table-body",
        "columns" => ["Delivery", "Kind", "Direction", "Provider State"]
      }
    }
  end

  defp provider_details(provider) do
    %{
      "configuration" => %{
        "id" => "provider-configuration",
        "title" => "Configuration",
        "rows" => [
          detail_dto("Provider type", humanize(provider.provider_type)),
          detail_dto(
            "Provider Account",
            binding_label(provider.provider_account_id, provider.provider_account_version),
            true
          ),
          detail_dto(
            "Mission Grant",
            binding_label(
              provider.provider_account_grant_id,
              provider.provider_account_grant_version
            ),
            true
          ),
          detail_dto("Validated", timestamp_label(provider.last_validated_at))
        ]
      },
      "delivery_policy" => %{
        "id" => "provider-delivery-policy",
        "title" => "Delivery Change Policy",
        "rows" => [
          detail_dto(
            "Mode",
            humanize(Map.get(provider.delivery_policy_document, "mode", "approval_required"))
          ),
          detail_dto(
            "Deadline behavior",
            humanize(
              Map.get(
                provider.delivery_policy_document,
                "deadline_behavior",
                "retain_last_accepted"
              )
            )
          ),
          detail_dto("Permitted resources", resource_summary(provider.permitted_resource_refs))
        ]
      },
      "capabilities" => capabilities_dto(provider),
      "version_history" => %{
        "id" => "provider-version-history",
        "title" => "Version History",
        "stream_id" => "provider-versions"
      }
    }
  end

  defp capabilities_dto(provider) do
    items =
      provider.capabilities_document
      |> Map.get("operations", %{})
      |> Enum.sort_by(fn {name, _supported?} -> name end)
      |> Enum.map(fn {capability, supported?} ->
        %{
          "label" => humanize(capability),
          "status" => %{
            "tone" => if(supported?, do: "ready", else: "blocked"),
            "label" => if(supported?, do: "Supported", else: "Unavailable")
          }
        }
      end)

    %{
      "id" => "provider-capabilities",
      "title" => "Capabilities",
      "empty" => items == [],
      "empty_copy" => "Validate the provider to load its declared capabilities.",
      "items" => items
    }
  end

  defp provider_diagnostics(provider) do
    %{
      "id" => "provider-admin-diagnostics",
      "label" => "Admin Diagnostics",
      "json_id" => "provider-admin-diagnostics-json",
      "rows" => [
        detail_dto("Account ID", provider.provider_account_id || "Legacy setup", true),
        detail_dto("Account version", version_label(provider.provider_account_version), true),
        detail_dto("Grant ID", provider.provider_account_grant_id || "Not granted", true),
        detail_dto("Grant version", version_label(provider.provider_account_grant_version), true)
      ],
      "json" => diagnostics_json(provider)
    }
  end

  defp detail_dto(label, value, mono? \\ false),
    do: %{"label" => label, "value" => value, "mono" => mono?}

  defp profile_items(provider, key) do
    case get_in(provider.inventory_sync_document, [key, "items"]) do
      items when is_list(items) -> normalize_profiles(key, items)
      _other -> []
    end
  end

  defp normalize_profiles("service_profiles", items),
    do: Enum.flat_map(items, &normalize_profile(&1, ServiceProfile))

  defp normalize_profiles("delivery_profiles", items),
    do: Enum.flat_map(items, &normalize_profile(&1, DeliveryProfile))

  defp normalize_profile(item, module) do
    case module.from_external(item) do
      {:ok, profile} -> [profile]
      {:error, _reason} -> []
    end
  end

  defp service_profile_dto(profile) do
    %{
      "__dom_id" => "service-profile-#{profile.id}",
      "id" => profile.id,
      "display_name" => profile.display_name,
      "service_kind" => profile.service_kind,
      "direction" => Atom.to_string(profile.direction),
      "data_families" => Enum.join(profile.data_families, ", "),
      "status" => %{
        "tone" => profile.state |> profile_status() |> Atom.to_string(),
        "label" => humanize(profile.state)
      }
    }
  end

  defp delivery_profile_dto(profile) do
    %{
      "__dom_id" => "delivery-profile-#{profile.id}",
      "id" => profile.id,
      "display_name" => profile.display_name,
      "operator_summary" => profile.operator_summary,
      "delivery_kind" => profile.delivery_kind,
      "direction" => Atom.to_string(profile.direction),
      "status" => %{
        "tone" => profile.state |> profile_status() |> Atom.to_string(),
        "label" => humanize(profile.state)
      }
    }
  end

  defp provider_version_dto(version),
    do: %{
      "__dom_id" => "provider-version-#{version.version}",
      "version" => version.version,
      "lifecycle_state" => version.lifecycle_state |> Atom.to_string() |> String.upcase()
    }

  defp diagnostics_json(provider) do
    %{
      "control_plane" => provider.metadata["control_plane"],
      "sync" => provider.metadata["sync"],
      "capabilities" => provider.capabilities_document,
      "inventory_summary" => inventory_counts(provider.inventory_sync_document),
      "service_profiles" =>
        provider |> profile_items("service_profiles") |> Enum.map(& &1.evidence),
      "delivery_profiles" =>
        provider |> profile_items("delivery_profiles") |> Enum.map(& &1.evidence)
    }
    |> RedactedJson.sanitize()
    |> Jason.encode!(pretty: true)
  end

  defp inventory_counts(document) do
    for key <- ["spacecraft", "ground_stations", "service_profiles", "delivery_profiles"],
        into: %{} do
      {key, Map.take(Map.get(document, key, %{}), ["total_count", "cached_count", "truncated"])}
    end
  end

  defp control_plane_status(provider) do
    case get_in(provider.metadata, ["control_plane", "status"]) do
      "healthy" -> :ready
      "failed" -> :attention
      _other -> :blocked
    end
  end

  defp control_plane_label(provider) do
    case get_in(provider.metadata, ["control_plane", "status"]) do
      "healthy" -> "Healthy"
      "failed" -> "Validation failed"
      _other -> "Not validated"
    end
  end

  defp account_binding_label(%{provider_account_id: nil}), do: "Legacy setup"

  defp account_binding_label(provider),
    do: "#{provider.provider_account_id} · v#{provider.provider_account_version}"

  defp grant_binding_label(%{provider_account_grant_id: nil}), do: "Not granted"

  defp grant_binding_label(provider),
    do: "#{provider.provider_account_grant_id} · v#{provider.provider_account_grant_version}"

  defp provider_type_label(%{provider_type: :simulator}), do: "Simulated"
  defp provider_type_label(provider), do: Atom.to_string(provider.provider_type)
  defp timestamp_label(nil), do: "Never"

  defp timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")

  defp binding_label(nil, _version), do: "Legacy setup"
  defp binding_label(id, version), do: "#{id} · v#{version}"
  defp version_label(nil), do: "Not available"
  defp version_label(version), do: "v#{version}"
  defp resource_summary([]), do: "Inherited from grant"
  defp resource_summary(resources), do: Enum.join(resources, ", ")
  defp profile_status(state) when state in [:active, :ready], do: :ready
  defp profile_status(:degraded), do: :attention
  defp profile_status(_state), do: :blocked
  defp humanize(value) when is_atom(value), do: value |> Atom.to_string() |> humanize()

  defp humanize(value) when is_binary(value),
    do:
      value
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp humanize(value), do: to_string(value)

  defp navigate_attrs(href, extra_attrs),
    do:
      Map.merge(
        %{"data-phx-link" => "redirect", "data-phx-link-state" => "push", "href" => href},
        extra_attrs
      )

  defp breadcrumb_separator,
    do: %{"attrs" => %{"class" => "text-base-content/20", "aria-hidden" => "true"}, "text" => "/"}

  defp fallback_href(mission_id, "provider_list", _subject),
    do: mission_href(mission_id, "/comms/providers")

  defp fallback_href(mission_id, "provider_new", _subject),
    do: mission_href(mission_id, "/comms/providers/new")

  defp fallback_href(mission_id, "provider_show", subject) when is_binary(subject),
    do: mission_href(mission_id, "/comms/providers/#{segment!(subject)}")

  defp fallback_href(mission_id, "provider_show", _subject),
    do: fallback_href(mission_id, "provider_list", nil)

  defp fallback_href(mission_id, "overview", _subject), do: mission_href(mission_id, "/comms")
  defp surface_label("provider_list"), do: "Providers"
  defp surface_label("provider_new"), do: "New Provider"
  defp surface_label("provider_show"), do: "Provider"
  defp mission_href(mission_id, suffix), do: "/missions/" <> segment!(mission_id) <> suffix
  defp segment!(value), do: validated_segment(value)

  defp validated_segment(value) do
    case Ids.path_segment(value) do
      {:ok, value} -> value
      {:error, :invalid_identifier} -> throw(:invalid_application_request)
    end
  end

  defp guarded(fun) do
    fun.()
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    :throw, :invalid_application_request -> {:error, :invalid_application_request}
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end
end
