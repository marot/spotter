defmodule Spotter.Transcripts.ResourcesReviewItemTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Commit,
    CommitHotspot,
    Project,
    ReviewItem
  }

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-review", pattern: "^test"})
    commit = Ash.create!(Commit, %{commit_hash: String.duplicate("r", 40)})

    hotspot =
      Ash.create!(CommitHotspot, %{
        project_id: project.id,
        commit_id: commit.id,
        relative_path: "lib/foo.ex",
        line_start: 1,
        line_end: 10,
        snippet: "def foo",
        reason: "complex",
        overall_score: 60.0,
        model_used: "test",
        analyzed_at: ~U[2026-02-13 12:00:00Z]
      })

    %{project: project, commit: commit, hotspot: hotspot}
  end

  describe "ReviewItem - commit_message target" do
    test "creates review item for commit message", %{project: project, commit: commit} do
      item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          commit_id: commit.id,
          importance: :high,
          next_due_on: ~D[2026-02-14],
          interval_days: 1
        })

      assert item.target_kind == :commit_message
      assert item.importance == :high
      assert item.seen_count == 0
      assert item.last_seen_at == nil
      assert item.suspended_at == nil
    end

    test "rejects commit_message without commit_id", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          importance: :medium
        })
      end
    end

    test "rejects commit_message with commit_hotspot_id", %{
      project: project,
      commit: commit,
      hotspot: hotspot
    } do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          commit_id: commit.id,
          commit_hotspot_id: hotspot.id
        })
      end
    end
  end

  describe "ReviewItem - commit_hotspot target" do
    test "creates review item for commit hotspot", %{
      project: project,
      commit: commit,
      hotspot: hotspot
    } do
      item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_hotspot,
          commit_id: commit.id,
          commit_hotspot_id: hotspot.id,
          importance: :low,
          next_due_on: ~D[2026-02-27],
          interval_days: 14
        })

      assert item.target_kind == :commit_hotspot
      assert item.importance == :low
    end

    test "rejects commit_hotspot without commit_hotspot_id", %{project: project, commit: commit} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_hotspot,
          commit_id: commit.id
        })
      end
    end
  end

  describe "ReviewItem - defaults and upsert" do
    test "defaults importance to medium", %{project: project, commit: commit} do
      item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          commit_id: commit.id
        })

      assert item.importance == :medium
    end

    test "upsert by identity returns same record for hotspot target", %{
      project: project,
      commit: commit,
      hotspot: hotspot
    } do
      attrs = %{
        project_id: project.id,
        target_kind: :commit_hotspot,
        commit_id: commit.id,
        commit_hotspot_id: hotspot.id,
        importance: :high
      }

      first = Ash.create!(ReviewItem, attrs)
      second = Ash.create!(ReviewItem, attrs)

      assert first.id == second.id
    end
  end

  describe "ReviewItem - mark_seen" do
    test "increments seen_count and sets last_seen_at", %{project: project, commit: commit} do
      item =
        Ash.create!(ReviewItem, %{
          project_id: project.id,
          target_kind: :commit_message,
          commit_id: commit.id
        })

      assert item.seen_count == 0
      assert item.last_seen_at == nil

      updated = Ash.update!(item, %{}, action: :mark_seen)
      assert updated.seen_count == 1
      assert updated.last_seen_at != nil

      updated2 = Ash.update!(updated, %{}, action: :mark_seen)
      assert updated2.seen_count == 2
    end
  end
end
