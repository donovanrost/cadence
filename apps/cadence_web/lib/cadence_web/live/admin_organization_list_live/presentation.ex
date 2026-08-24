defmodule CadenceWeb.AdminOrganizationListLive.Presentation do
  @moduledoc false
  use CadenceWeb, :html

  @doc false
  def build(organizations) do
    rows = Enum.map(organizations, &organization_row/1)

    create_organization_attrs =
      navigate_attrs(~p"/admin/organizations/new", %{"class" => "btn btn-primary btn-sm"})

    %{
      root: %{
        attrs: raw_attrs(%{"id" => "admin-organizations-page", "class" => "space-y-6"})
      },
      header: %{
        root: %{
          attrs: raw_attrs(%{"class" => "border-b border-primary/20 pb-4"})
        },
        layout: %{
          attrs: raw_attrs(%{"class" => "flex items-end justify-between gap-4"})
        },
        content: %{attrs: %{}},
        breadcrumbs: %{
          root: %{
            attrs:
              raw_attrs(%{
                "aria-label" => "Breadcrumb",
                "class" =>
                  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
              })
          },
          items: [
            %{
              separator: nil,
              kind: "link",
              content: %{
                attrs:
                  navigate_attrs(~p"/admin", %{
                    "class" => "hover:text-primary transition-colors"
                  }),
                text: "Platform Admin"
              }
            },
            %{
              separator: %{
                attrs:
                  raw_attrs(%{
                    "aria-hidden" => "true",
                    "class" => "text-base-content/20"
                  }),
                text: "/"
              },
              kind: "current",
              content: %{
                attrs: raw_attrs(%{"class" => "text-primary/90"}),
                text: "Organizations"
              }
            }
          ]
        },
        title: %{
          attrs:
            raw_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          text: "Organizations"
        },
        actions: %{
          attrs: raw_attrs(%{"class" => "flex items-center gap-2"})
        },
        create_action: %{
          attrs: create_organization_attrs,
          text: "Create organization"
        }
      },
      empty_state: empty_state_presentation(rows, create_organization_attrs),
      card: card_presentation(rows)
    }
  end

  @doc false
  def raw_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp empty_state_presentation([], create_organization_attrs) do
    %{
      root: %{
        attrs:
          raw_attrs(%{
            "class" =>
              "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
          })
      },
      title: %{
        attrs: raw_attrs(%{"class" => "hud-label"}),
        text: "No organizations yet"
      },
      description: %{
        attrs:
          raw_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        text: "Create one to bring a customer onto the platform."
      },
      action_container: %{
        attrs: raw_attrs(%{"class" => "mt-5"})
      },
      action: %{
        attrs: create_organization_attrs,
        text: "Create organization"
      },
      action_icon: %{
        attrs: raw_attrs(%{"class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"})
      }
    }
  end

  defp empty_state_presentation(_rows, _create_organization_attrs), do: nil

  defp card_presentation([]), do: nil

  defp card_presentation(rows) do
    %{
      root: %{
        attrs: raw_attrs(%{"class" => "card bg-base-200 border border-base-300"})
      },
      body: %{
        attrs: raw_attrs(%{"class" => "card-body p-0"})
      },
      child: %{
        attrs: raw_attrs(%{"id" => "admin-organization-list-component"})
      },
      rows: rows
    }
  end

  defp navigate_attrs(href, extra_attrs) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
    |> Map.merge(extra_attrs)
    |> raw_attrs()
  end

  defp organization_row(organization) do
    %{
      id: "admin-organization-#{organization.organization_id}",
      display_name: organization.display_name,
      slug: organization.slug,
      href: ~p"/admin/organizations/#{organization.organization_id}"
    }
  end
end
