defmodule Spotter.Services.HeatmapCalculatorTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.HeatmapCalculator
  alias Spotter.Transcripts.{FileHeatmap, FileSnapshot, Project, Session}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, opts \\ []) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id,
      cwd: opts[:cwd],
      started_at: opts[:started_at]
    })
  end

  defp create_snapshot(session, opts) do
    Ash.create!(FileSnapshot, %{
      session_id: session.id,
      tool_use_id: opts[:tool_use_id] || Ash.UUID.generate(),
      file_path: opts[:file_path] || opts[:relative_path] || "lib/foo.ex",
      relative_path: opts[:relative_path],
      change_type: opts[:change_type] || :modified,
      source: opts[:source] || :edit,
      timestamp: opts[:timestamp] || ~U[2026-01-15 12:00:00Z]
    })
  end

  defp read_heatmaps(project_id) do
    FileHeatmap
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.read!()
  end

  describe "calculate_heat_score/3" do
    test "returns expected score for known inputs" do
      # 20 changes, changed today
      reference = ~U[2026-02-01 12:00:00Z]
      score = HeatmapCalculator.calculate_heat_score(20, reference, reference)
      # frequency_norm = min(log(21) / log(21), 1.0) = 1.0
      # recency_norm = exp(0) = 1.0
      # score = (0.65 * 1.0 + 0.35 * 1.0) * 100 = 100.0
      assert score == 100.0
    end

    test "returns lower score for old changes" do
      reference = ~U[2026-02-01 12:00:00Z]
      last_changed = ~U[2026-01-04 12:00:00Z]
      score = HeatmapCalculator.calculate_heat_score(1, last_changed, reference)
      # 28 days ago, 1 change
      # frequency_norm = log(2) / log(21) ~= 0.2276
      # recency_norm = exp(-28/14) = exp(-2) ~= 0.1353
      # score = (0.65 * 0.2276 + 0.35 * 0.1353) * 100 ~= 19.53
      assert_in_delta score, 19.53, 0.5
    end

    test "score is 0 for zero changes at distant time" do
      reference = ~U[2026-02-01 12:00:00Z]
      last_changed = ~U[2025-01-01 00:00:00Z]
      score = HeatmapCalculator.calculate_heat_score(0, last_changed, reference)
      # frequency_norm = log(1) / log(21) = 0
      # recency_norm ~= 0 (very old)
      assert score < 1.0
    end

    test "frequency caps at 1.0 for 20+ changes" do
      reference = ~U[2026-02-01 12:00:00Z]
      last_changed = ~U[2026-01-18 12:00:00Z]
      score_20 = HeatmapCalculator.calculate_heat_score(20, last_changed, reference)
      score_100 = HeatmapCalculator.calculate_heat_score(100, last_changed, reference)
      # Both should have frequency_norm = 1.0 (capped)
      assert_in_delta score_20, score_100, 0.01
    end
  end

  describe "compute/2" do
    test "creates heatmap rows from snapshots" do
      project = create_project("heatmap-snap")
      session = create_session(project)

      create_snapshot(session,
        relative_path: "lib/a.ex",
        timestamp: ~U[2026-02-01 10:00:00Z]
      )

      create_snapshot(session,
        relative_path: "lib/a.ex",
        timestamp: ~U[2026-02-01 11:00:00Z]
      )

      create_snapshot(session,
        relative_path: "lib/b.ex",
        timestamp: ~U[2026-02-01 10:00:00Z]
      )

      reference = ~U[2026-02-01 12:00:00Z]
      assert :ok = HeatmapCalculator.compute(project.id, reference_date: reference)

      heatmaps = read_heatmaps(project.id)
      assert length(heatmaps) == 2

      a_row = Enum.find(heatmaps, &(&1.relative_path == "lib/a.ex"))
      b_row = Enum.find(heatmaps, &(&1.relative_path == "lib/b.ex"))

      assert a_row.change_count_30d == 2
      assert b_row.change_count_30d == 1
      assert a_row.heat_score > b_row.heat_score
    end

    test "filters binary files" do
      project = create_project("heatmap-binary")
      session = create_session(project)

      create_snapshot(session,
        relative_path: "lib/code.ex",
        timestamp: ~U[2026-02-01 10:00:00Z]
      )

      create_snapshot(session,
        relative_path: "assets/logo.png",
        timestamp: ~U[2026-02-01 10:00:00Z]
      )

      assert :ok =
               HeatmapCalculator.compute(project.id, reference_date: ~U[2026-02-01 12:00:00Z])

      heatmaps = read_heatmaps(project.id)
      assert length(heatmaps) == 1
      assert hd(heatmaps).relative_path == "lib/code.ex"
    end

    test "deletes stale rows outside window" do
      project = create_project("heatmap-stale")
      session = create_session(project)

      # Create an old heatmap row that won't have data in window
      Ash.create!(FileHeatmap, %{
        project_id: project.id,
        relative_path: "old_file.ex",
        change_count_30d: 5,
        heat_score: 50.0,
        last_changed_at: ~U[2025-12-01 00:00:00Z]
      })

      # Create a snapshot for a different file in window
      create_snapshot(session,
        relative_path: "new_file.ex",
        timestamp: ~U[2026-02-01 10:00:00Z]
      )

      assert :ok =
               HeatmapCalculator.compute(project.id, reference_date: ~U[2026-02-01 12:00:00Z])

      heatmaps = read_heatmaps(project.id)
      paths = Enum.map(heatmaps, & &1.relative_path)
      assert "new_file.ex" in paths
      refute "old_file.ex" in paths
    end

    test "works for project with no sessions (snapshot-only)" do
      project = create_project("heatmap-empty")

      assert :ok =
               HeatmapCalculator.compute(project.id, reference_date: ~U[2026-02-01 12:00:00Z])

      assert read_heatmaps(project.id) == []
    end

    test "upserts existing heatmap rows on re-run" do
      project = create_project("heatmap-upsert")
      session = create_session(project)

      create_snapshot(session,
        relative_path: "lib/x.ex",
        timestamp: ~U[2026-02-01 10:00:00Z]
      )

      reference = ~U[2026-02-01 12:00:00Z]
      assert :ok = HeatmapCalculator.compute(project.id, reference_date: reference)
      assert length(read_heatmaps(project.id)) == 1

      # Add another snapshot and re-run
      create_snapshot(session,
        relative_path: "lib/x.ex",
        timestamp: ~U[2026-02-01 11:00:00Z]
      )

      assert :ok = HeatmapCalculator.compute(project.id, reference_date: reference)
      heatmaps = read_heatmaps(project.id)
      assert length(heatmaps) == 1
      assert hd(heatmaps).change_count_30d == 2
    end
  end
end
