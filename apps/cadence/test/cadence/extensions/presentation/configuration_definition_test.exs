defmodule Cadence.Extensions.Presentation.ConfigurationDefinitionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Extensions.Presentation.{
    ConfigurationDefinition,
    FieldDefinition,
    SectionDefinition
  }

  test "validates bounded fields and their compiled visibility dependencies" do
    definition = valid_definition()

    assert :ok = ConfigurationDefinition.validate(definition)

    assert ConfigurationDefinition.default_params(definition) == %{
             "host" => "",
             "mode" => "listen"
           }
  end

  test "rejects duplicate fields and unresolved visibility dependencies" do
    definition = valid_definition()
    [section] = definition.sections

    duplicate_fields = %ConfigurationDefinition{
      definition
      | sections: [section, %SectionDefinition{section | id: "duplicate-section"}]
    }

    assert {:error, :invalid_configuration_definition} =
             ConfigurationDefinition.validate(duplicate_fields)

    [mode, host] = section.fields

    unresolved_visibility = %ConfigurationDefinition{
      definition
      | sections: [
          %SectionDefinition{
            section
            | fields: [
                mode,
                %FieldDefinition{host | visible_when: %{field: :missing, equals: "x"}}
              ]
          }
        ]
    }

    assert {:error, :invalid_configuration_definition} =
             ConfigurationDefinition.validate(unresolved_visibility)
  end

  test "rejects unsupported presentation vocabulary" do
    definition = valid_definition()
    [section] = definition.sections
    [mode, host] = section.fields

    invalid_field = %{host | type: :custom_html}

    assert {:error, :invalid_configuration_definition} =
             ConfigurationDefinition.validate(%ConfigurationDefinition{
               definition
               | sections: [%SectionDefinition{section | fields: [mode, invalid_field]}]
             })
  end

  defp valid_definition do
    %ConfigurationDefinition{
      id: "test-configuration",
      description: "A bounded host-rendered configuration.",
      sections: [
        %SectionDefinition{
          id: "connection",
          number: "01",
          title: "Connection",
          fields: [
            %FieldDefinition{
              field: :mode,
              label: "Mode",
              type: :select,
              required: true,
              default: "listen",
              options: [{"Listen", "listen"}, {"Connect", "connect"}]
            },
            %FieldDefinition{
              field: :host,
              label: "Host",
              type: :text,
              visible_when: %{field: :mode, equals: "connect"}
            }
          ]
        }
      ]
    }
  end
end
