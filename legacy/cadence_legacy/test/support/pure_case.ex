defmodule Cadence.PureCase do
  @moduledoc """
  Test case for pure unit tests that do NOT require database access.

  ## Test Pyramid

  Cadence follows a test pyramid structure:

  ```
            /\\        E2E Tests (LiveView, browser)
           /  \\
          /----\\      Integration Tests (DataCase - real database)
         /------\\
        /--------\\    Use Case Tests (PureCase + fake adapters)
       /----------\\
      /------------\\  Pure Unit Tests (PureCase - domain entities)
  ```

  ### Layer 1: Pure Unit Tests (This Case)

  Test domain entities, value objects, and pure functions without any
  external dependencies:

      defmodule Cadence.Domain.Alerting.Entities.AlarmTest do
        use Cadence.PureCase

        test "acknowledge transitions from active to acknowledged" do
          {:ok, alarm} = Alarm.new(valid_attrs())
          {:ok, acked} = Alarm.acknowledge(alarm, "user-123")
          assert acked.status == :acknowledged
        end
      end

  ### Layer 2: Use Case Tests (This Case + Fake Adapters)

  Test application layer use cases with fake/in-memory adapters:

      defmodule Cadence.Application.Alerting.AlarmOperationsTest do
        use Cadence.PureCase, async: false

        setup do
          {:ok, _} = InMemoryAlarmRepository.start_link()
          Application.put_env(:cadence, :alarm_repository, InMemoryAlarmRepository)
          on_exit(fn -> InMemoryAlarmRepository.stop() end)
          :ok
        end

        test "acknowledge_alarm updates status and records event" do
          alarm = insert_test_alarm()
          {:ok, acked} = AlarmOperations.acknowledge(alarm.id, "user-123", nil)
          assert acked.status == :acknowledged
        end
      end

  ### Layer 3: Integration Tests (DataCase)

  Test with real database for adapter implementations and constraint testing.
  Use `Cadence.DataCase` for these tests.

  ### Layer 4: E2E Tests (ConnCase)

  Test full request/response cycles with `Cadence.ConnCase`.

  ## Available Fake Adapters

  - `Cadence.Test.Adapters.InMemoryAlarmRepository` - Alarm persistence
  - `Cadence.Test.Adapters.InMemoryQueueRepository` - Queue persistence
  - `Cadence.Test.Adapters.InMemoryProcedureRepository` - Procedure persistence
  - `Cadence.Test.Adapters.InMemoryEventRecorder` - Event recording
  - `Cadence.Test.Adapters.FakeEmailSender` - Email sending
  - `Cadence.Test.Adapters.FakeEventPublisher` - PubSub events

  ## Why Use PureCase?

  1. **Speed** - No database setup/teardown, tests run instantly
  2. **Isolation** - Tests don't depend on database state
  3. **Architecture enforcement** - Forces domain logic to be pure
  4. **Parallel execution** - All tests can run async: true by default

  ## What NOT to Test Here

  - Anything that requires Ecto/Repo
  - Integration tests that span multiple layers
  - Tests that need real database constraints (unique indexes, etc.)

  For those, use `Cadence.DataCase` instead.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Cadence.PureCase

      # Intentionally NO Ecto imports - this is for pure domain tests
      # If you need Ecto, you should use DataCase instead
    end
  end

  setup tags do
    if use_in_memory_adapters?(tags) do
      cleanup = Cadence.TestSupport.enable_in_memory_adapters()
      on_exit(cleanup)
    end

    :ok
  end

  alias Cadence.TestSupport.VirtualTime

  @doc """
  Adds a setup block that switches Cadence time to virtual for the test.
  """
  defmacro setup_virtual_time(opts \\ []) do
    quote do
      setup do
        %{cleanup: cleanup} = VirtualTime.setup(unquote(opts))
        on_exit(cleanup)
        :ok
      end
    end
  end

  @doc """
  Adds a setup block that ensures the MissionRegistry is running.
  """
  defmacro setup_mission_registry do
    quote do
      setup do
        case Process.whereis(Cadence.MissionRegistry) do
          nil -> start_supervised!({Registry, keys: :unique, name: Cadence.MissionRegistry})
          _pid -> :ok
        end

        :ok
      end
    end
  end

  @doc """
  Adds a setup block that ensures the telemetry limits cache is running.
  """
  defmacro setup_limits_cache do
    quote do
      setup do
        case Process.whereis(Cadence.Runtime.Telemetry.Limits.Cache) do
          nil -> start_supervised!({Cadence.Runtime.Telemetry.Limits.Cache, []})
          _pid -> :ok
        end

        :ok
      end
    end
  end

  defp use_in_memory_adapters?(tags) do
    if tags[:no_in_memory_adapters] do
      false
    else
      Application.get_env(:cadence, :use_in_memory_adapters, false)
    end
  end

  @doc """
  Generates a random UUID for use in tests.

  This is a pure function that doesn't require the database.
  """
  def random_id do
    Ecto.UUID.generate()
  end

  @doc """
  Generates a unique integer for use in test data.
  """
  def unique_integer do
    System.unique_integer([:positive])
  end

  @doc """
  Generates a unique string with the given prefix.

  ## Example

      unique_string("alarm") # => "alarm_12345"
  """
  def unique_string(prefix \\ "test") do
    "#{prefix}_#{unique_integer()}"
  end

  @doc """
  Generates a unique email address for tests.
  """
  def unique_email do
    "user-#{Ecto.UUID.generate()}@example.com"
  end

  @doc """
  Returns the current UTC timestamp.
  """
  def now do
    DateTime.utc_now()
  end

  @doc """
  Returns a timestamp in the past.

  ## Example

      ago(5, :minutes)
      ago(1, :hour)
      ago(2, :days)
  """
  def ago(amount, unit) do
    seconds =
      case unit do
        :second -> amount
        :seconds -> amount
        :minute -> amount * 60
        :minutes -> amount * 60
        :hour -> amount * 3600
        :hours -> amount * 3600
        :day -> amount * 86_400
        :days -> amount * 86_400
      end

    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end

  @doc """
  Returns a timestamp in the future.

  ## Example

      from_now(5, :minutes)
      from_now(1, :hour)
  """
  def from_now(amount, unit) do
    seconds =
      case unit do
        :second -> amount
        :seconds -> amount
        :minute -> amount * 60
        :minutes -> amount * 60
        :hour -> amount * 3600
        :hours -> amount * 3600
        :day -> amount * 86_400
        :days -> amount * 86_400
      end

    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  @doc """
  Asserts that a function eventually returns a truthy value.

  Useful for testing async operations with fake adapters.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 1000)
  - `:interval` - Time between checks in milliseconds (default: 10)

  ## Example

      assert_eventually(fn -> FakeEmailSender.sent_count() > 0 end, timeout: 500)
  """
  def assert_eventually(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 10)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(fun, deadline, interval)
  end

  defp do_assert_eventually(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(interval)
        do_assert_eventually(fun, deadline, interval)
      else
        raise ExUnit.AssertionError,
          message: "Condition was not met within timeout"
      end
    end
  end
end
