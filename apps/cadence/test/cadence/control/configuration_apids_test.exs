defmodule Cadence.Control.ConfigurationApidsTest do
  use ExUnit.Case, async: true

  alias Cadence.Control.ConfigurationApids

  defp entry(apids), do: %{"document" => %{"handled_apids" => apids}}

  describe "changes/3" do
    test "nil expands to the catalog's APIDs; only a real change or a stray is reported" do
      effective = %{
        "wider" => %{"catalog_revision_id" => "rev", "handled_apids" => nil},
        "same" => %{"catalog_revision_id" => "rev", "handled_apids" => [43, 42]},
        "stray" => %{"catalog_revision_id" => "rev", "handled_apids" => [42, 99]},
        "unmanaged" => %{"catalog_revision_id" => nil, "handled_apids" => nil}
      }

      entries = %{
        "wider" => entry([42]),
        "same" => entry([42, 43]),
        "stray" => entry([42]),
        "unmanaged" => entry([42])
      }

      assert ConfigurationApids.changes(effective, entries, %{"rev" => [42, 43]}) == %{
               "wider" => %{from: [42], to: [42, 43], stray: []},
               "stray" => %{from: [42], to: [42, 99], stray: [99]}
             }
    end

    test "derivations take only changes without strays" do
      changes = %{
        "wider" => %{from: [42], to: [42, 43], stray: []},
        "stray" => %{from: [42], to: [42, 99], stray: [99]}
      }

      assert ConfigurationApids.derivations(changes) == %{
               "wider" => %{"handled_apids" => [42, 43]}
             }
    end
  end
end
