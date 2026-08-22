defmodule CadenceWeb.ListParamsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.ListParams

  @opts [sortable: ~w(display_name scid), default_sort: "display_name"]

  describe "parse/2" do
    test "applies defaults for empty params" do
      list = ListParams.parse(%{}, @opts)

      assert list.q == nil
      assert list.sort == "display_name"
      assert list.dir == :asc
      assert list.page == 1
    end

    test "trims the query and blanks become nil" do
      assert ListParams.parse(%{"q" => "  alpha "}, @opts).q == "alpha"
      assert ListParams.parse(%{"q" => "   "}, @opts).q == nil
    end

    test "whitelists sort and rejects unknown directions" do
      assert ListParams.parse(%{"sort" => "scid", "dir" => "desc"}, @opts).sort == "scid"
      assert ListParams.parse(%{"sort" => "drop table"}, @opts).sort == "display_name"
      assert ListParams.parse(%{"dir" => "sideways"}, @opts).dir == :asc
    end

    test "clamps page to a positive integer" do
      assert ListParams.parse(%{"page" => "3"}, @opts).page == 3
      assert ListParams.parse(%{"page" => "0"}, @opts).page == 1
      assert ListParams.parse(%{"page" => "banana"}, @opts).page == 1
    end
  end

  describe "toggle_sort/2" do
    test "flips direction on the active column and resets the page" do
      list = %{ListParams.parse(%{"sort" => "scid", "page" => "3"}, @opts) | page: 3}

      toggled = ListParams.toggle_sort(list, "scid")

      assert toggled.dir == :desc
      assert toggled.page == 1
    end

    test "switching columns resets to ascending" do
      list = ListParams.parse(%{"sort" => "scid", "dir" => "desc"}, @opts)

      toggled = ListParams.toggle_sort(list, "display_name")

      assert toggled.sort == "display_name"
      assert toggled.dir == :asc
    end
  end

  describe "to_query/2" do
    test "drops defaults so bare URLs stay canonical" do
      assert ListParams.parse(%{}, @opts) |> ListParams.to_query() == []
    end

    test "keeps non-default state and extras, dropping nil extras" do
      list = ListParams.parse(%{"q" => "alpha", "sort" => "scid", "dir" => "desc"}, @opts)

      query = ListParams.to_query(list, filter: "missing_profile", noop: nil)

      assert query == [q: "alpha", sort: "scid", dir: "desc", filter: "missing_profile"]
    end

    test "keeps the default sort column when direction is descending" do
      list = ListParams.parse(%{"sort" => "display_name", "dir" => "desc"}, @opts)

      assert ListParams.to_query(list) == [sort: "display_name", dir: "desc"]
    end
  end
end
