defmodule CadenceWeb.CommsProviderListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Management.Providers

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    providers = Providers.list_providers(scope.organization_id, mission.mission_id)
    provider_table_rows = Enum.map(providers, &provider_table_row(&1, mission.mission_id))
    provider_count = length(providers)
    providers_empty? = providers == []

    {:ok,
     socket
     |> assign(:page_title, "Ground Network Providers")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_count, provider_count)
     |> assign(:providers_empty?, providers_empty?)
     |> assign(:provider_table_rows, provider_table_rows)
     |> assign(
       :presentation,
       presentation_dto(mission, provider_count, providers_empty?, provider_table_rows)
     )
     |> stream_configure(:providers, dom_id: &"mission-provider-#{&1.provider_id}")
     |> stream(:providers, providers)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-provider-list-component"
        v-component="CommsProviderList"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp presentation_dto(mission, provider_count, providers_empty?, rows) do
    new_provider_path = ~p"/missions/#{mission.mission_id}/comms/providers/new"

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "comms-providers-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(mission, provider_count, new_provider_path),
      "empty_state" => empty_state_presentation(providers_empty?, new_provider_path),
      "card" => card_presentation(providers_empty?, rows)
    }
  end

  defp header_presentation(mission, provider_count, new_provider_path) do
    %{
      "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-end justify-between gap-4"})
      },
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => breadcrumbs_presentation(mission),
      "title" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
          }),
        "text" => "Ground Network Providers",
        "suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "#{provider_count} configured"
        }
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" =>
          "Provider control planes for scheduling, inventory discovery, and delivery profile negotiation."
      },
      "actions" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
        "new_provider" => %{
          "attrs" =>
            navigate_attrs(new_provider_path, %{
              "id" => "new-provider-link",
              "class" => "btn btn-primary btn-sm gap-1"
            }),
          "icon" => %{
            "attrs" => presentation_attrs(%{"class" => "hero-plus h-4 w-4"})
          },
          "text" => "New Provider"
        }
      }
    }
  end

  defp breadcrumbs_presentation(mission) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "aria-label" => "Breadcrumb",
          "class" =>
            "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        }),
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{
            "attrs" =>
              navigate_attrs(~p"/missions/#{mission.mission_id}", %{
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
              navigate_attrs(~p"/missions/#{mission.mission_id}/comms", %{
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
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Providers"
          }
        }
      ]
    }
  end

  defp breadcrumb_separator do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" => "text-base-content/20",
          "aria-hidden" => "true"
        }),
      "text" => "/"
    }
  end

  defp empty_state_presentation(true, new_provider_path) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" =>
            "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        }),
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label"}),
        "text" => "No ground network providers"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" =>
          "Connect this mission to a simulator or commercial ground network control plane."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" => navigate_attrs(new_provider_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"
            })
        },
        "text" => "Configure the first provider"
      }
    }
  end

  defp empty_state_presentation(false, _new_provider_path), do: nil

  defp card_presentation(true, _rows), do: nil

  defp card_presentation(false, rows) do
    %{
      "attrs" => presentation_attrs(%{"class" => "card bg-base-200 border border-base-300"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "card-body p-0"})
      },
      "table_component" => %{
        "attrs" => presentation_attrs(%{"id" => "mission-providers-table-component"})
      },
      "rows" => rows
    }
  end

  defp navigate_attrs(href, extra_attrs) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
    |> Map.merge(extra_attrs)
    |> presentation_attrs()
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

  defp timestamp_label(nil), do: "Never"

  defp timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")

  defp account_binding_label(%{provider_account_id: nil}), do: "Legacy setup"

  defp account_binding_label(provider),
    do: "#{provider.provider_account_id} · v#{provider.provider_account_version}"

  defp grant_binding_label(%{provider_account_grant_id: nil}), do: "Not granted"

  defp grant_binding_label(provider),
    do: "#{provider.provider_account_grant_id} · v#{provider.provider_account_grant_version}"

  defp provider_table_row(provider, mission_id) do
    %{
      id: "mission-provider-#{provider.provider_id}",
      display_name: provider.display_name,
      provider_type: provider_type_label(provider),
      server_url: provider.base_url,
      status: Atom.to_string(control_plane_status(provider)),
      status_label: control_plane_label(provider),
      account_binding: account_binding_label(provider),
      grant_binding: grant_binding_label(provider),
      last_synced_at: timestamp_label(provider.last_synced_at),
      version: "v#{provider.version}",
      href: ~p"/missions/#{mission_id}/comms/providers/#{provider.provider_id}"
    }
  end

  defp provider_type_label(%{provider_type: :simulator}), do: "Simulated"
  defp provider_type_label(provider), do: Atom.to_string(provider.provider_type)
end
