defmodule Spotter.Agents.TestToolsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Agents.TestTools.{CreateTest, DeleteTest, ListTests, UpdateTest}
  alias Spotter.Transcripts.Project

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "tool-tests", pattern: "^test"})

    %{project: project}
  end

  describe "list_tests" do
    test "returns empty list for no tests", %{project: project} do
      {:ok, result} =
        ListTests.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/foo_test.exs"
        })

      assert %{"tests" => []} = decode_result(result)
    end
  end

  describe "create_test then list" do
    test "created test appears in list", %{project: project} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/foo_test.exs",
          "framework" => "ExUnit",
          "test_name" => "returns ok",
          "describe_path" => ["FooTest"],
          "given" => ["a valid input"],
          "when" => ["calling foo/1"],
          "then" => ["returns :ok"],
          "confidence" => 0.9
        })

      created = decode_result(create_result)["test"]
      assert created["test_name"] == "returns ok"
      assert created["framework"] == "ExUnit"
      assert created["given"] == ["a valid input"]

      {:ok, list_result} =
        ListTests.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/foo_test.exs"
        })

      tests = decode_result(list_result)["tests"]
      assert length(tests) == 1
      assert hd(tests)["id"] == created["id"]
    end
  end

  describe "update_test" do
    test "modifies given/when/then", %{project: project} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/bar_test.exs",
          "framework" => "ExUnit",
          "test_name" => "original"
        })

      test_id = decode_result(create_result)["test"]["id"]

      {:ok, update_result} =
        UpdateTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/bar_test.exs",
          "test_id" => test_id,
          "patch" => %{
            "given" => ["updated given"],
            "when" => ["updated when"],
            "then" => ["updated then"]
          }
        })

      updated = decode_result(update_result)["test"]
      assert updated["given"] == ["updated given"]
      assert updated["when"] == ["updated when"]
      assert updated["then"] == ["updated then"]
    end

    test "returns error for wrong file", %{project: project} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/real_test.exs",
          "framework" => "ExUnit",
          "test_name" => "test1"
        })

      test_id = decode_result(create_result)["test"]["id"]

      assert {:error, "test_not_in_file"} =
               UpdateTest.execute(%{
                 "project_id" => project.id,
                 "relative_path" => "test/wrong_file.exs",
                 "test_id" => test_id,
                 "patch" => %{"test_name" => "renamed"}
               })
    end
  end

  describe "delete_test" do
    test "removes test", %{project: project} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/del_test.exs",
          "framework" => "ExUnit",
          "test_name" => "to delete"
        })

      test_id = decode_result(create_result)["test"]["id"]

      {:ok, delete_result} =
        DeleteTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/del_test.exs",
          "test_id" => test_id
        })

      assert %{"ok" => true} = decode_result(delete_result)

      {:ok, list_result} =
        ListTests.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/del_test.exs"
        })

      assert %{"tests" => []} = decode_result(list_result)
    end

    test "returns error for wrong file", %{project: project} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project.id,
          "relative_path" => "test/real_test.exs",
          "framework" => "ExUnit",
          "test_name" => "test2"
        })

      test_id = decode_result(create_result)["test"]["id"]

      assert {:error, "test_not_in_file"} =
               DeleteTest.execute(%{
                 "project_id" => project.id,
                 "relative_path" => "test/wrong_file.exs",
                 "test_id" => test_id
               })
    end
  end

  defp decode_result(%{"content" => [%{"type" => "text", "text" => json}]}) do
    Jason.decode!(json)
  end
end
