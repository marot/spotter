defmodule SpotterWeb.PaneListLiveStudyQueueTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, CommitHotspot, Project, ReviewItem}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-study", pattern: "^test"})

    commit =
      Ash.create!(Commit, %{
        commit_hash: String.duplicate("a", 40),
        subject: "Add feature X"
      })

    hotspot =
      Ash.create!(CommitHotspot, %{
        project_id: project.id,
        commit_id: commit.id,
        relative_path: "lib/foo.ex",
        line_start: 10,
        line_end: 25,
        snippet: "def run do\n  :ok\nend",
        reason: "Complex logic",
        overall_score: 75.0,
        rubric: %{"complexity" => 80},
        model_used: "claude-opus-4-6",
        analyzed_at: DateTime.utc_now()
      })

    message_item =
      Ash.create!(ReviewItem, %{
        project_id: project.id,
        target_kind: :commit_message,
        commit_id: commit.id,
        importance: :medium,
        interval_days: 4,
        next_due_on: Date.utc_today()
      })

    hotspot_item =
      Ash.create!(ReviewItem, %{
        project_id: project.id,
        target_kind: :commit_hotspot,
        commit_id: commit.id,
        commit_hotspot_id: hotspot.id,
        importance: :high,
        interval_days: 1,
        next_due_on: Date.utc_today()
      })

    %{
      project: project,
      commit: commit,
      hotspot: hotspot,
      message_item: message_item,
      hotspot_item: hotspot_item
    }
  end

  describe "mark_seen" do
    test "increments seen_count and advances schedule", %{message_item: item} do
      assert item.seen_count == 0

      Ash.update!(item, %{}, action: :mark_seen)
      updated = Ash.get!(ReviewItem, item.id)

      assert updated.seen_count == 1
      assert updated.last_seen_at != nil
    end
  end

  describe "set_importance" do
    test "updates importance and resets schedule for high", %{message_item: item} do
      Ash.update!(item, %{
        importance: :high,
        interval_days: 1,
        next_due_on: Date.add(Date.utc_today(), 1)
      })

      updated = Ash.get!(ReviewItem, item.id)
      assert updated.importance == :high
      assert updated.interval_days == 1
      assert updated.next_due_on == Date.add(Date.utc_today(), 1)
    end

    test "updates importance and resets schedule for low", %{hotspot_item: item} do
      Ash.update!(item, %{
        importance: :low,
        interval_days: 14,
        next_due_on: Date.add(Date.utc_today(), 14)
      })

      updated = Ash.get!(ReviewItem, item.id)
      assert updated.importance == :low
      assert updated.interval_days == 14
    end
  end

  describe "due items loading" do
    test "loads due items for today", %{project: project} do
      today = Date.utc_today()

      items =
        ReviewItem
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.Query.filter(is_nil(suspended_at))
        |> Ash.Query.filter(next_due_on <= ^today)
        |> Ash.read!()

      assert length(items) == 2
    end

    test "excludes suspended items", %{message_item: item, project: project} do
      today = Date.utc_today()
      Ash.update!(item, %{suspended_at: DateTime.utc_now()})

      items =
        ReviewItem
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.Query.filter(is_nil(suspended_at))
        |> Ash.Query.filter(next_due_on <= ^today)
        |> Ash.read!()

      assert length(items) == 1
    end

    test "excludes future items", %{message_item: item, project: project} do
      today = Date.utc_today()
      Ash.update!(item, %{next_due_on: Date.add(Date.utc_today(), 10)})

      items =
        ReviewItem
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.Query.filter(is_nil(suspended_at))
        |> Ash.Query.filter(next_due_on <= ^today)
        |> Ash.read!()

      assert length(items) == 1
    end
  end
end
