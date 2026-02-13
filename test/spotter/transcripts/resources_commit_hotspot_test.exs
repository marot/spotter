defmodule Spotter.Transcripts.ResourcesCommitHotspotTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Commit,
    CommitHotspot,
    Project
  }

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-hotspot", pattern: "^test"})
    commit = Ash.create!(Commit, %{commit_hash: String.duplicate("a", 40)})

    %{project: project, commit: commit}
  end

  describe "CommitHotspot" do
    test "creates a commit hotspot", %{project: project, commit: commit} do
      hotspot =
        Ash.create!(CommitHotspot, %{
          project_id: project.id,
          commit_id: commit.id,
          relative_path: "lib/foo.ex",
          line_start: 10,
          line_end: 20,
          snippet: "def foo, do: :bar",
          reason: "Complex conditional logic",
          overall_score: 75.0,
          rubric: %{"complexity" => 80, "error_handling" => 70},
          model_used: "claude-sonnet-4-5-20250929",
          analyzed_at: ~U[2026-02-13 12:00:00Z]
        })

      assert hotspot.relative_path == "lib/foo.ex"
      assert hotspot.line_start == 10
      assert hotspot.line_end == 20
      assert hotspot.snippet == "def foo, do: :bar"
      assert hotspot.reason == "Complex conditional logic"
      assert hotspot.overall_score == 75.0
      assert hotspot.rubric == %{"complexity" => 80, "error_handling" => 70}
      assert hotspot.model_used == "claude-sonnet-4-5-20250929"
      assert hotspot.metadata == %{}
      assert hotspot.symbol_name == nil
    end

    test "allows optional symbol_name", %{project: project, commit: commit} do
      hotspot =
        Ash.create!(CommitHotspot, %{
          project_id: project.id,
          commit_id: commit.id,
          relative_path: "lib/foo.ex",
          line_start: 10,
          line_end: 20,
          snippet: "def foo, do: :bar",
          reason: "Named function",
          overall_score: 50.0,
          model_used: "claude-sonnet-4-5-20250929",
          analyzed_at: ~U[2026-02-13 12:00:00Z],
          symbol_name: "Foo.bar/2"
        })

      assert hotspot.symbol_name == "Foo.bar/2"
    end

    test "upsert by identity with symbol_name returns same record", %{
      project: project,
      commit: commit
    } do
      attrs = %{
        project_id: project.id,
        commit_id: commit.id,
        relative_path: "lib/foo.ex",
        line_start: 10,
        line_end: 20,
        snippet: "def foo, do: :bar",
        reason: "reason",
        overall_score: 50.0,
        model_used: "claude-sonnet-4-5-20250929",
        analyzed_at: ~U[2026-02-13 12:00:00Z],
        symbol_name: "Foo.bar/2"
      }

      first = Ash.create!(CommitHotspot, attrs)
      second = Ash.create!(CommitHotspot, attrs)

      assert first.id == second.id
    end

    test "different line ranges create separate records", %{project: project, commit: commit} do
      base = %{
        project_id: project.id,
        commit_id: commit.id,
        relative_path: "lib/foo.ex",
        snippet: "code",
        reason: "reason",
        overall_score: 50.0,
        model_used: "claude-sonnet-4-5-20250929",
        analyzed_at: ~U[2026-02-13 12:00:00Z]
      }

      h1 = Ash.create!(CommitHotspot, Map.merge(base, %{line_start: 10, line_end: 20}))
      h2 = Ash.create!(CommitHotspot, Map.merge(base, %{line_start: 30, line_end: 40}))

      assert h1.id != h2.id
    end

    test "rejects overall_score outside 0-100 range", %{project: project, commit: commit} do
      base = %{
        project_id: project.id,
        commit_id: commit.id,
        relative_path: "lib/foo.ex",
        line_start: 1,
        line_end: 5,
        snippet: "code",
        reason: "reason",
        model_used: "test",
        analyzed_at: ~U[2026-02-13 12:00:00Z]
      }

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(CommitHotspot, Map.put(base, :overall_score, 101.0))
      end

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(CommitHotspot, Map.put(base, :overall_score, -1.0))
      end
    end

    test "stores metadata", %{project: project, commit: commit} do
      hotspot =
        Ash.create!(CommitHotspot, %{
          project_id: project.id,
          commit_id: commit.id,
          relative_path: "lib/foo.ex",
          line_start: 1,
          line_end: 5,
          snippet: "code",
          reason: "reason",
          overall_score: 50.0,
          model_used: "test",
          analyzed_at: ~U[2026-02-13 12:00:00Z],
          metadata: %{"pipeline" => "small", "chunk_index" => 0}
        })

      assert hotspot.metadata == %{"pipeline" => "small", "chunk_index" => 0}
    end
  end
end
