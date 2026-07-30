defmodule CadenceWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.Layouts

  test "renders controller flashes through the LiveToast host" do
    document =
      render_component(&Layouts.auth/1,
        flash: %{"error" => "The supplied credentials were rejected."},
        inner_content: "Sign-in page"
      )
      |> LazyHTML.from_fragment()

    host = LazyHTML.query(document, "#toast-group")
    toast = LazyHTML.query(host, "#flash-error[role='alert'][phx-hook='LiveToast']")

    assert ["error"] = LazyHTML.attribute(toast, "data-kind")
    assert LazyHTML.text(toast) =~ "The supplied credentials were rejected."
  end
end
