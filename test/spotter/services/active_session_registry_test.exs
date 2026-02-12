defmodule Spotter.Services.ActiveSessionRegistryTest do
  use ExUnit.Case, async: false

  alias Spotter.Services.ActiveSessionRegistry

  @table Spotter.Services.ActiveSessionRegistry

  setup do
    # Clean up ETS between tests
    :ets.delete_all_objects(@table)
    :ok
  end

  defp unique_session_id, do: "session-#{System.unique_integer([:positive])}"

  describe "start_session/2" do
    test "inserts an active session into ETS" do
      session_id = unique_session_id()
      assert :ok = ActiveSessionRegistry.start_session(session_id, "%1")

      assert [{^session_id, "%1", _last_hook_at, nil, nil, :active}] =
               :ets.lookup(@table, session_id)
    end

    test "broadcasts session_activity on start" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")
      session_id = unique_session_id()

      ActiveSessionRegistry.start_session(session_id, "%1")

      assert_receive {:session_activity, %{session_id: ^session_id, status: _status}}
    end
  end

  describe "touch/2" do
    test "updates last_hook_at for tracked session" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      [{^session_id, _, initial_ts, _, _, _}] = :ets.lookup(@table, session_id)

      Process.sleep(10)
      ActiveSessionRegistry.touch(session_id, :tool_call)

      [{^session_id, _, updated_ts, _, _, _}] = :ets.lookup(@table, session_id)
      assert updated_ts >= initial_ts
    end

    test "is a no-op for unknown sessions" do
      assert :ok = ActiveSessionRegistry.touch("unknown-session", :hook)
    end
  end

  describe "end_session/2" do
    test "marks session as ended" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      assert :ok = ActiveSessionRegistry.end_session(session_id, "user_exit")

      [{^session_id, "%1", _last, ended_at, "user_exit", :ended}] =
        :ets.lookup(@table, session_id)

      assert ended_at != nil
    end

    test "is idempotent for repeated end calls" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      assert :ok = ActiveSessionRegistry.end_session(session_id, "first")
      assert :ok = ActiveSessionRegistry.end_session(session_id, "second")

      [{^session_id, "%1", _, _, "second", :ended}] = :ets.lookup(@table, session_id)
    end

    test "handles unknown session without crashing" do
      session_id = unique_session_id()
      assert :ok = ActiveSessionRegistry.end_session(session_id, "unknown")

      [{^session_id, nil, _, _, "unknown", :ended}] = :ets.lookup(@table, session_id)
    end

    test "handles nil reason" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      assert :ok = ActiveSessionRegistry.end_session(session_id)

      [{^session_id, "%1", _, _, nil, :ended}] = :ets.lookup(@table, session_id)
    end

    test "broadcasts session_activity on end" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")
      ActiveSessionRegistry.end_session(session_id, "done")

      assert_receive {:session_activity, %{session_id: ^session_id, status: :ended}}
    end
  end

  describe "status/1" do
    test "returns nil for untracked session" do
      assert nil == ActiveSessionRegistry.status("nonexistent")
    end

    test "returns ended status for ended session" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")
      ActiveSessionRegistry.end_session(session_id, "done")

      info = ActiveSessionRegistry.status(session_id)
      assert info.status == :ended
      assert info.ended_reason == "done"
      assert info.session_id == session_id
    end

    test "returns active status for recently touched session" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      info = ActiveSessionRegistry.status(session_id)
      # Active because last_hook_at is recent (even if pane not present)
      assert info.status == :active
    end
  end

  describe "status_map/1" do
    test "returns map of session statuses" do
      s1 = unique_session_id()
      s2 = unique_session_id()
      ActiveSessionRegistry.start_session(s1, "%1")
      ActiveSessionRegistry.start_session(s2, "%2")
      ActiveSessionRegistry.end_session(s2, "done")

      map = ActiveSessionRegistry.status_map([s1, s2])

      assert map[s1].status == :active
      assert map[s2].status == :ended
    end

    test "returns nil for unknown sessions in map" do
      map = ActiveSessionRegistry.status_map(["unknown"])
      assert map["unknown"] == nil
    end
  end

  describe "sweep" do
    test "evicts stale active entries past TTL" do
      session_id = unique_session_id()
      stale_ts = System.monotonic_time(:second) - 91

      :ets.insert(@table, {session_id, "%99", stale_ts, nil, nil, :active})

      send(ActiveSessionRegistry, :sweep)
      Process.sleep(50)

      assert :ets.lookup(@table, session_id) == []
    end

    test "does not evict ended sessions" do
      session_id = unique_session_id()
      stale_ts = System.monotonic_time(:second) - 200

      :ets.insert(@table, {session_id, "%99", stale_ts, stale_ts, "done", :ended})

      send(ActiveSessionRegistry, :sweep)
      Process.sleep(50)

      assert :ets.lookup(@table, session_id) != []
    end

    test "does not evict recent active sessions" do
      session_id = unique_session_id()
      ActiveSessionRegistry.start_session(session_id, "%1")

      send(ActiveSessionRegistry, :sweep)
      Process.sleep(50)

      assert :ets.lookup(@table, session_id) != []
    end
  end
end
