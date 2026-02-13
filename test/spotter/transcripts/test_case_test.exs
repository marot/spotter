defmodule Spotter.Transcripts.TestCaseTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Commit,
    Project,
    TestCase
  }

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-cases", pattern: "^test"})
    commit = Ash.create!(Commit, %{commit_hash: String.duplicate("b", 40)})

    %{project: project, commit: commit}
  end

  describe "create" do
    test "creates with full fields", %{project: project, commit: commit} do
      tc =
        Ash.create!(TestCase, %{
          project_id: project.id,
          source_commit_id: commit.id,
          relative_path: "test/foo_test.exs",
          framework: "ExUnit",
          describe_path: ["FooTest", "some context"],
          test_name: "returns ok",
          line_start: 10,
          line_end: 25,
          given: ["a valid user"],
          when: ["calling foo/1"],
          then: ["returns :ok"],
          confidence: 0.85,
          metadata: %{"agent_model" => "sonnet"}
        })

      assert tc.relative_path == "test/foo_test.exs"
      assert tc.framework == "ExUnit"
      assert tc.describe_path == ["FooTest", "some context"]
      assert tc.test_name == "returns ok"
      assert tc.line_start == 10
      assert tc.line_end == 25
      assert tc.given == ["a valid user"]
      assert tc.when == ["calling foo/1"]
      assert tc.then == ["returns :ok"]
      assert tc.confidence == 0.85
      assert tc.metadata == %{"agent_model" => "sonnet"}
      assert tc.project_id == project.id
      assert tc.source_commit_id == commit.id
    end

    test "creates with minimal fields", %{project: project} do
      tc =
        Ash.create!(TestCase, %{
          project_id: project.id,
          relative_path: "test/bar_test.exs",
          framework: "ExUnit",
          test_name: "works"
        })

      assert tc.describe_path == []
      assert tc.given == []
      assert tc.when == []
      assert tc.then == []
      assert tc.confidence == nil
      assert tc.metadata == %{}
      assert tc.source_commit_id == nil
    end

    test "upsert identity prevents duplicates", %{project: project} do
      attrs = %{
        project_id: project.id,
        relative_path: "test/foo_test.exs",
        framework: "ExUnit",
        describe_path: ["FooTest"],
        test_name: "returns ok"
      }

      first = Ash.create!(TestCase, attrs)
      second = Ash.create!(TestCase, attrs)

      assert first.id == second.id
    end
  end

  describe "line range validation" do
    test "rejects line_end < line_start", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(TestCase, %{
          project_id: project.id,
          relative_path: "test/foo_test.exs",
          framework: "ExUnit",
          test_name: "bad range",
          line_start: 20,
          line_end: 10
        })
      end
    end

    test "rejects line_start < 1", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(TestCase, %{
          project_id: project.id,
          relative_path: "test/foo_test.exs",
          framework: "ExUnit",
          test_name: "zero start",
          line_start: 0,
          line_end: 10
        })
      end
    end

    test "allows nil line range", %{project: project} do
      tc =
        Ash.create!(TestCase, %{
          project_id: project.id,
          relative_path: "test/foo_test.exs",
          framework: "ExUnit",
          test_name: "no lines"
        })

      assert tc.line_start == nil
      assert tc.line_end == nil
    end
  end

  describe "update" do
    test "updates mutable fields", %{project: project} do
      tc =
        Ash.create!(TestCase, %{
          project_id: project.id,
          relative_path: "test/foo_test.exs",
          framework: "ExUnit",
          test_name: "original"
        })

      updated =
        Ash.update!(tc, %{
          test_name: "updated",
          given: ["new given"],
          confidence: 0.9
        })

      assert updated.test_name == "updated"
      assert updated.given == ["new given"]
      assert updated.confidence == 0.9
    end
  end
end
