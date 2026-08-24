defmodule CadenceWeb.AdminOrganizationListLive.PresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.AdminOrganizationListLive.Presentation

  test "empty presentation preserves the complete Admin Organization List page contract" do
    presentation = Presentation.build([])

    assert presentation == %{
             root: %{
               attrs: %{"class" => "space-y-6", "id" => "admin-organizations-page"}
             },
             header: %{
               root: %{
                 attrs: %{"class" => "border-b border-primary/20 pb-4"}
               },
               layout: %{
                 attrs: %{"class" => "flex items-end justify-between gap-4"}
               },
               content: %{attrs: %{}},
               breadcrumbs: %{
                 root: %{
                   attrs: %{
                     "aria-label" => "Breadcrumb",
                     "class" =>
                       "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
                   }
                 },
                 items: [
                   %{
                     separator: nil,
                     kind: "link",
                     content: %{
                       attrs: %{
                         "class" => "hover:text-primary transition-colors",
                         "data-phx-link" => "redirect",
                         "data-phx-link-state" => "push",
                         "href" => "/admin"
                       },
                       text: "Platform Admin"
                     }
                   },
                   %{
                     separator: %{
                       attrs: %{
                         "aria-hidden" => "true",
                         "class" => "text-base-content/20"
                       },
                       text: "/"
                     },
                     kind: "current",
                     content: %{
                       attrs: %{"class" => "text-primary/90"},
                       text: "Organizations"
                     }
                   }
                 ]
               },
               title: %{
                 attrs: %{
                   "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
                 },
                 text: "Organizations"
               },
               actions: %{
                 attrs: %{"class" => "flex items-center gap-2"}
               },
               create_action: %{
                 attrs: %{
                   "class" => "btn btn-primary btn-sm",
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/admin/organizations/new"
                 },
                 text: "Create organization"
               }
             },
             empty_state: %{
               root: %{
                 attrs: %{
                   "class" =>
                     "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
                 }
               },
               title: %{
                 attrs: %{"class" => "hud-label"},
                 text: "No organizations yet"
               },
               description: %{
                 attrs: %{
                   "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
                 },
                 text: "Create one to bring a customer onto the platform."
               },
               action_container: %{
                 attrs: %{"class" => "mt-5"}
               },
               action: %{
                 attrs: %{
                   "class" => "btn btn-primary btn-sm",
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/admin/organizations/new"
                 },
                 text: "Create organization"
               },
               action_icon: %{
                 attrs: %{"class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"}
               }
             },
             card: nil
           }

    encoded = Jason.encode!(presentation)

    assert is_binary(encoded)
    assert Jason.decode!(encoded)["card"] == nil
    refute encoded =~ "admin-organization-list-component"
  end

  test "non-empty presentation preserves server ordering and every immutable child row field" do
    presentation =
      Presentation.build([
        organization("org-zulu", "Zulu Operations", "zulu"),
        organization("org-alpha", "Alpha Operations", "alpha")
      ])

    assert presentation.empty_state == nil

    assert presentation.card.child == %{
             attrs: %{"id" => "admin-organization-list-component"}
           }

    assert presentation.card.rows == [
             %{
               id: "admin-organization-org-zulu",
               display_name: "Zulu Operations",
               slug: "zulu",
               href: "/admin/organizations/org-zulu"
             },
             %{
               id: "admin-organization-org-alpha",
               display_name: "Alpha Operations",
               slug: "alpha",
               href: "/admin/organizations/org-alpha"
             }
           ]

    assert Jason.decode!(Jason.encode!(presentation))["card"]["rows"] == [
             %{
               "display_name" => "Zulu Operations",
               "href" => "/admin/organizations/org-zulu",
               "id" => "admin-organization-org-zulu",
               "slug" => "zulu"
             },
             %{
               "display_name" => "Alpha Operations",
               "href" => "/admin/organizations/org-alpha",
               "id" => "admin-organization-org-alpha",
               "slug" => "alpha"
             }
           ]
  end

  test "raw attrs preserve HEEx nil false true empty string string and number semantics" do
    assert Presentation.raw_attrs(%{
             "data-nil" => nil,
             "data-false" => false,
             "data-true" => true,
             "data-empty" => "",
             "data-string" => "retained",
             "data-number" => 42
           }) == %{
             "data-true" => "",
             "data-empty" => "",
             "data-string" => "retained",
             "data-number" => "42"
           }
  end

  defp organization(organization_id, display_name, slug) do
    %{organization_id: organization_id, display_name: display_name, slug: slug}
  end
end
