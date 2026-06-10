defmodule CadenceWeb.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias CadenceWeb.Components.Badges
  alias CadenceWeb.Components.Button
  alias CadenceWeb.Components.Card
  alias CadenceWeb.Components.FormInputs
  alias CadenceWeb.Components.PageHeader
  alias CadenceWeb.Components.Table

  describe "button/1" do
    test "primary default carries glow and small size" do
      html = render_button(%{})

      assert html =~ "btn-primary"
      assert html =~ "hover-glow-cyan"
      assert html =~ "transition-glow"
      assert html =~ "btn-sm"
      assert html =~ ~s(type="button")
    end

    test "ghost variant never glows" do
      html = render_button(%{variant: :ghost})

      assert html =~ "btn-ghost"
      refute html =~ "hover-glow-cyan"
    end

    test "danger variant renders outline error treatment" do
      html = render_button(%{variant: :danger})

      assert html =~ "btn-error"
      assert html =~ "btn-outline"
    end

    test "md size emits no size class" do
      html = render_button(%{size: :md})

      refute html =~ "btn-sm"
      refute html =~ "btn-xs"
    end

    test "renders a link when navigate is set" do
      html = render_button(%{navigate: "/missions"})

      assert html =~ "<a"
      assert html =~ ~s(href="/missions")
      assert html =~ "btn-primary"
      refute html =~ "<button"
    end

    defp render_button(attrs) do
      assigns = %{attrs: attrs}

      render_component(
        &Button.button/1,
        Map.merge(%{inner_block: text_slot("Go")}, assigns.attrs)
      )
    end
  end

  describe "card/1" do
    test "always renders canonical chrome with default padding" do
      html =
        render_component(&Card.card/1, id: "my-card", inner_block: text_slot("Body"))

      assert html =~ "card bg-base-200 border border-base-300 hud-corners"
      assert html =~ "p-6"
      assert html =~ ~s(id="my-card")
      assert html =~ "Body"
    end

    test "padding :none renders flush body" do
      html = render_component(&Card.card/1, padding: :none, inner_block: text_slot("Body"))

      assert html =~ "p-0"
      refute html =~ "p-6"
    end

    test "title mode renders hud-label heading" do
      html = render_component(&Card.card/1, title: "Database", inner_block: text_slot("Body"))

      assert html =~ "hud-label"
      assert html =~ "Database"
    end

    test "heading mode renders header bar with subtitle and actions" do
      html =
        render_component(&Card.card/1,
          heading: "Vehicles",
          subtitle: "3 total",
          actions: text_slot("New"),
          inner_block: text_slot("Body")
        )

      assert html =~ "border-b border-base-300 px-4 py-3"
      assert html =~ "Vehicles"
      assert html =~ "3 total"
      assert html =~ "New"
    end

    test "accent renders status left border" do
      html =
        render_component(&Card.card/1, accent: :warning, inner_block: text_slot("Body"))

      assert html =~ "border-l-2 border-l-warning/60"
    end

    test "stat_tile renders label over mono value" do
      html = render_component(&Card.stat_tile/1, label: "Vehicles", value: 4)

      assert html =~ "hud-label"
      assert html =~ "font-mono"
      assert html =~ "Vehicles"
      assert html =~ "4"
    end
  end

  describe "table/1" do
    test "renders hud-label headers and list rows" do
      html =
        render_component(&Table.table/1,
          id: "things-table",
          rows: [%{name: "Alpha"}, %{name: "Bravo"}],
          col: [
            %{
              label: "Name",
              inner_block: fn _changed, item -> item_text(item.name) end,
              __slot__: :col
            }
          ]
        )

      assert html =~ ~s(<table id="things-table" class="table)
      assert html =~ "hud-label"
      assert html =~ "Name"
      assert html =~ "Alpha"
      assert html =~ "Bravo"
      assert html =~ "hover:border-l-primary/60"
    end

    test "right-aligned mono column gets alignment and mono classes" do
      html =
        render_component(&Table.table/1,
          id: "t",
          rows: [%{v: "v1"}],
          row_accent: false,
          col: [
            %{
              label: "Version",
              align: :right,
              mono: true,
              inner_block: fn _changed, item -> item_text(item.v) end,
              __slot__: :col
            }
          ]
        )

      assert html =~ "text-right"
      assert html =~ "font-mono text-sm"
      refute html =~ "hover:border-l-primary/60"
    end

    test "empty slot renders when rows are empty" do
      html =
        render_component(&Table.table/1,
          id: "t",
          rows: [],
          col: [
            %{
              label: "Name",
              inner_block: fn _changed, _item -> item_text("x") end,
              __slot__: :col
            }
          ],
          empty: text_slot("Nothing here")
        )

      assert html =~ "Nothing here"
    end
  end

  describe "page_header/1" do
    test "renders title block over the standard border rule" do
      html =
        render_component(&PageHeader.page_header/1,
          title: "Transports",
          subtitle: "Byte movers",
          back_label: "Comms",
          back_navigate: "/comms"
        )

      assert html =~ "border-b border-primary/20 pb-4"
      assert html =~ "Transports"
      assert html =~ "Byte movers"
      assert html =~ "Comms"
      assert html =~ ~s(href="/comms")
    end

    test "renders breadcrumbs and actions" do
      html =
        render_component(&PageHeader.page_header/1,
          title: "DB-1",
          breadcrumbs: [{"Catalog", "/catalog"}, {"DB-1", nil}],
          actions: text_slot("Add revision")
        )

      assert html =~ "Breadcrumb"
      assert html =~ "Catalog"
      assert html =~ "Add revision"
      assert html =~ "justify-between"
    end
  end

  describe "input/1 standalone mode" do
    test "renders text input from name/value without a form field" do
      html =
        render_component(&FormInputs.input/1,
          name: "filter",
          value: "apid",
          label: "Filter",
          id: "filter-box"
        )

      assert html =~ ~s(name="filter")
      assert html =~ ~s(value="apid")
      assert html =~ ~s(id="filter-box")
      assert html =~ "hud-label"
      refute html =~ "input-error"
    end

    test "renders standalone select with options and selection" do
      html =
        render_component(&FormInputs.input/1,
          type: "select",
          name: "revision",
          value: "r2",
          options: [{"Revision 1", "r1"}, {"Revision 2", "r2"}]
        )

      assert html =~ "<select"
      assert html =~ ~s(name="revision")
      assert html =~ ~s(<option value="r2" selected>)
    end

    test "form field mode still renders errors when used" do
      form = to_form(%{"title" => ""}, as: :post)
      field = %{form[:title] | errors: [{"can't be blank", []}]}

      html = render_component(&FormInputs.input/1, field: field, label: "Title")

      assert html =~ ~s(name="post[title]")
      assert html =~ "can&#39;t be blank"
      assert html =~ "input-error"
    end
  end

  describe "badges" do
    test "status_badge auto-labels from status" do
      html = render_component(&Badges.status_badge/1, status: :ready)

      assert html =~ "Ready"
      assert html =~ "bg-success/20 text-success"
    end

    test "status_badge accepts a custom label" do
      html = render_component(&Badges.status_badge/1, status: :attention, label: "Profile drift")

      assert html =~ "Profile drift"
      assert html =~ "bg-warning/20 text-warning"
    end

    test "severity_badge renders count and label" do
      html = render_component(&Badges.severity_badge/1, severity: :critical, count: 3)

      assert html =~ "3"
      assert html =~ "CRIT"
      assert html =~ "bg-error/20 text-error"
    end
  end

  defp text_slot(text) do
    [%{inner_block: fn _changed, _arg -> item_text(text) end, __slot__: :inner_block}]
  end

  defp item_text(text) do
    assigns = %{text: text}

    ~H"{@text}"
  end
end
