defmodule Spotter.Transcripts.CommitTestRunTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Commit,
    CommitTestRun,
    Project
  }

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-runs", pattern: "^test"})
    commit = Ash.create!(Commit, %{commit_hash: String.duplicate("c", 40)})

    %{project: project, commit: commit}
  end

  describe "create" do
    test "creates with defaults", %{project: project, commit: commit} do
      run =
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })

      assert run.status == :queued
      assert run.model_used == nil
      assert run.input_stats == %{}
      assert run.output_stats == %{}
      assert run.error == nil
      assert run.started_at == nil
      assert run.completed_at == nil
    end
  end

  describe "mark_running" do
    test "sets status and started_at", %{project: project, commit: commit} do
      run =
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })

      updated = Ash.update!(run, %{}, action: :mark_running)

      assert updated.status == :running
      assert updated.started_at != nil
    end
  end

  describe "complete" do
    test "sets completed state", %{project: project, commit: commit} do
      run =
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })

      run = Ash.update!(run, %{}, action: :mark_running)

      completed =
        Ash.update!(
          run,
          %{
            model_used: "claude-sonnet-4-5-20250929",
            input_stats: %{"files" => 3, "diff_lines" => 120},
            output_stats: %{"created" => 5, "updated" => 2, "deleted" => 1}
          },
          action: :complete
        )

      assert completed.status == :completed
      assert completed.completed_at != nil
      assert completed.error == nil
      assert completed.model_used == "claude-sonnet-4-5-20250929"
      assert completed.input_stats == %{"files" => 3, "diff_lines" => 120}
      assert completed.output_stats == %{"created" => 5, "updated" => 2, "deleted" => 1}
    end
  end

  describe "fail" do
    test "sets error state", %{project: project, commit: commit} do
      run =
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })

      run = Ash.update!(run, %{}, action: :mark_running)

      failed = Ash.update!(run, %{error: "Agent timed out"}, action: :fail)

      assert failed.status == :error
      assert failed.completed_at != nil
      assert failed.error == "Agent timed out"
    end
  end

  describe "identity" do
    test "enforces unique project+commit", %{project: project, commit: commit} do
      Ash.create!(CommitTestRun, %{
        project_id: project.id,
        commit_id: commit.id
      })

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(CommitTestRun, %{
          project_id: project.id,
          commit_id: commit.id
        })
      end
    end
  end
end
