defmodule CadenceWeb.LayoutsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias CadenceWeb.Layouts

  test "production layout loads the split JavaScript entry as a module" do
    document =
      render_component(&Layouts.root/1, inner_content: "page")
      |> LazyHTML.from_document()

    assert ["module"] =
             document
             |> LazyHTML.query("head script[src='/assets/app.js']")
             |> LazyHTML.attribute("type")
  end

  test "each layout sends one shell variant and semantic context" do
    for variant <- [:auth, :sidebar, :mission_sidebar, :ops, :user_shell] do
      html = render_component(&apply(Layouts, variant, [&1]), flash: %{}, inner_content: "page")
      vue = LiveVue.Test.get_vue(html, id: "application-shell")
      assert vue.component == "ApplicationShell"
      refute vue.ssr
      assert vue.props["variant"] == Atom.to_string(variant)
      assert vue.props["context"]["notifications"] == []
      assert is_binary(vue.props["context"]["csrf_token"])
      refute Map.has_key?(vue.props, "presentation")
    end
  end

  test "renders controller flashes through the LiveToast transport" do
    document =
      render_component(&Layouts.auth/1, flash: %{"error" => "Rejected"}, inner_content: "page")
      |> LazyHTML.from_fragment()

    assert ["error"] =
             document
             |> LazyHTML.query("#flash-error[role=alert][phx-hook=LiveToast]")
             |> LazyHTML.attribute("data-kind")
  end

  test "shell context does not expose credentials or internal resource fields" do
    context =
      CadenceWeb.HostContext.from_assigns(%{
        current_scope: %{
          user: %{
            user_id: "u",
            email: "u@example.test",
            display_name: "User",
            password_hash: "secret"
          },
          organization: %{organization_id: "o", display_name: "Org", settings: %{secret: true}},
          capabilities: MapSet.new([:organization_admin]),
          admin_mode?: false
        },
        current_mission: %{
          mission_id: "m",
          display_name: "Mission",
          slug: "mission",
          internal: "private"
        }
      })

    assert context.user == %{user_id: "u", email: "u@example.test", display_name: "User"}
    assert context.organization == %{organization_id: "o", display_name: "Org"}
    assert context.mission == %{mission_id: "m", display_name: "Mission", slug: "mission"}
    assert context.capabilities == [:organization_admin]
    assert Jason.encode!(context)
  end
end
