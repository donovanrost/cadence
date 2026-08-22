defmodule Cadence.Extensions.ExtensionPackageTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Extensions.{
    ApplicationContribution,
    CapabilityContribution,
    ExtensionPackage,
    PackageDependency
  }

  test "validates a bounded package envelope with typed contributions" do
    package = valid_package()

    assert :ok = ExtensionPackage.validate(package)
  end

  test "rejects duplicate contributions and untyped dependencies" do
    package = valid_package()
    [application, capability] = package.contributions

    assert {:error, :invalid_extension_package} =
             ExtensionPackage.validate(%ExtensionPackage{
               package
               | contributions: [application, application, capability]
             })

    assert {:error, :invalid_extension_package} =
             ExtensionPackage.validate(%ExtensionPackage{package | dependencies: [%{}]})
  end

  test "requires compatibility contracts for every contribution family" do
    package = valid_package()

    assert {:error, :invalid_extension_package} =
             ExtensionPackage.validate(%ExtensionPackage{
               package
               | compatibility: %{cadence_application_contract: 1}
             })

    assert {:error, :invalid_extension_package} =
             ExtensionPackage.validate(%ExtensionPackage{
               package
               | compatibility: %{
                   cadence_application_contract: 1,
                   cadence_capability_abi: 2
                 }
             })
  end

  test "rejects self dependencies before package resolution" do
    package = valid_package()

    dependency = %PackageDependency{package_id: package.package_id}

    assert {:error, :invalid_extension_package} =
             ExtensionPackage.validate(%ExtensionPackage{
               package
               | dependencies: [dependency]
             })
  end

  defp valid_package do
    %ExtensionPackage{
      package_id: "cadence.example",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_application_contract: 1,
        cadence_capability_abi: 1
      },
      contributions: [
        %ApplicationContribution{
          application_key: "example",
          application_version: 1
        },
        %CapabilityContribution{
          family_key: :example,
          family_version: 1,
          kind: :managed_application
        }
      ]
    }
  end
end
