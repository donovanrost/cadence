defmodule Cadence.Reads.ApplicationSurfaces.TablePaginationTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.SurfaceElements.Table
  alias Cadence.Listing.Page
  alias Cadence.Reads.ApplicationSurfaces.TablePagination

  test "bounds pages and normalizes client-supplied page values" do
    items = Enum.to_list(1..25)

    assert {:ok, %Page{page: 1, page_size: 20, total_count: 25, items: first_page}} =
             TablePagination.paginate(items, %{"page" => "invalid"})

    assert first_page == Enum.to_list(1..20)

    assert {:ok, %Page{page: 2, items: second_page}} =
             TablePagination.paginate(items, %{"page" => "999"})

    assert second_page == Enum.to_list(21..25)
  end

  test "rejects page sizes above the host bound" do
    assert {:error, :invalid_application_surface_page_size} =
             TablePagination.paginate([], %{}, page_size: 51)
  end

  test "rejects malformed or duplicate table rows" do
    valid = %Table{
      id: "bounded-table",
      title: "Bounded table",
      columns: [%{key: :name, label: "Name", mono: false}],
      page: %Page{
        items: [%{id: "row-1", name: "One"}],
        total_count: 1,
        page: 1,
        page_size: 20
      },
      empty_title: "No rows"
    }

    assert :ok = Table.validate(valid)

    duplicate_page = %Page{
      valid.page
      | items: [%{id: "row-1", name: "One"}, %{id: "row-1", name: "Duplicate"}],
        total_count: 2
    }

    assert {:error, :invalid_application_surface_table} =
             Table.validate(%Table{valid | page: duplicate_page})

    missing_cell_page = %Page{valid.page | items: [%{id: "row-1"}]}

    assert {:error, :invalid_application_surface_table} =
             Table.validate(%Table{valid | page: missing_cell_page})

    duplicate_columns = [
      %{key: :name, label: "Name", mono: false},
      %{key: :name, label: "Duplicate name", mono: true}
    ]

    assert {:error, :invalid_application_surface_table} =
             Table.validate(%Table{valid | columns: duplicate_columns})
  end
end
