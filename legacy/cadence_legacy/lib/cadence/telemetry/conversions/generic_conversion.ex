defmodule Cadence.Telemetry.Conversions.GenericConversion do
  @moduledoc """
  Generic conversion using a custom Elixir module.

  For complex conversions that don't fit polynomial or state table patterns.
  The specified module must implement the Converter behaviour.

  ## Examples

      # Custom temperature conversion with nonlinear lookup table
      %GenericConversion{
        module_name: "MyMission.Conversions.ThermistorLookup",
        config: %{
          "lookup_table_id" => "NTC_10K_B3950"
        }
      }

      # Time conversion with leap second handling
      %GenericConversion{
        module_name: "Cadence.Conversions.GPSTime",
        config: %{
          "epoch" => "2000-01-01T00:00:00Z"
        }
      }

  ## Module Requirements

  The custom module must implement:

      defmodule MyMission.Conversions.ThermistorLookup do
        @behaviour Cadence.Telemetry.Conversions.ConverterBehaviour

        @impl true
        def convert(raw_value, config) do
          # Perform custom conversion logic
          {:ok, converted_value}
        end
      end
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "generic_conversions" do
    # Module name (e.g., "MyApp.Conversions.CustomTemp")
    field :module_name, :string

    # Optional configuration JSON passed to the module
    field :config, :map

    belongs_to :conversion, Cadence.Telemetry.Conversions.Conversion

    timestamps()
  end

  @doc """
  Creates a changeset for a generic conversion.
  """
  def changeset(generic_conversion, attrs) do
    generic_conversion
    |> cast(attrs, [:conversion_id, :module_name, :config])
    |> validate_required([:conversion_id, :module_name])
    |> validate_module_name()
    |> unique_constraint(:conversion_id)
  end

  defp validate_module_name(changeset) do
    case get_field(changeset, :module_name) do
      nil ->
        changeset

      module_name when is_binary(module_name) ->
        # Validate that it looks like a valid module name
        if module_name =~ ~r/^[A-Z][A-Za-z0-9.]*$/ do
          changeset
        else
          add_error(changeset, :module_name, "must be a valid Elixir module name")
        end

      _ ->
        add_error(changeset, :module_name, "must be a string")
    end
  end
end
