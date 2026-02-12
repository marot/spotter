defmodule Spotter.Services.ReviewSessionRegistryTest do
  use ExUnit.Case, async: false

  alias Spotter.Services.ReviewSessionRegistry

  @table :review_session_registry

  defp unique_name, do: "test-review-#{System.unique_integer([:positive])}"

  describe "register/heartbeat/deregister" do
    test "register creates ETS entry" do
      name = unique_name()
      ReviewSessionRegistry.register(name)

      assert [{^name, _ts}] = :ets.lookup(@table, name)

      :ets.delete(@table, name)
    end

    test "heartbeat updates timestamp" do
      name = unique_name()
      ReviewSessionRegistry.register(name)
      [{_, ts1}] = :ets.lookup(@table, name)

      Process.sleep(10)
      ReviewSessionRegistry.heartbeat(name)
      [{_, ts2}] = :ets.lookup(@table, name)

      assert ts2 >= ts1

      :ets.delete(@table, name)
    end

    test "deregister removes entry" do
      name = unique_name()
      ReviewSessionRegistry.register(name)
      ReviewSessionRegistry.deregister(name)

      assert :ets.lookup(@table, name) == []
    end
  end

  describe "sweep" do
    test "evicts stale entries past TTL" do
      name = unique_name()
      stale_ts = System.monotonic_time(:second) - 31
      :ets.insert(@table, {name, stale_ts})

      send(ReviewSessionRegistry, :sweep)
      Process.sleep(50)

      assert :ets.lookup(@table, name) == []
    end

    test "retains fresh entries" do
      name = unique_name()
      ReviewSessionRegistry.register(name)

      send(ReviewSessionRegistry, :sweep)
      Process.sleep(50)

      assert [{^name, _ts}] = :ets.lookup(@table, name)

      :ets.delete(@table, name)
    end
  end
end
