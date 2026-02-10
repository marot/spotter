defmodule Spotter.Transcripts.ResourcesTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Message, Project, Session, Subagent}

  setup do
    Sandbox.checkout(Repo)
  end

  describe "Project" do
    test "creates and reads a project" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      assert project.name == "test"
      assert project.pattern == "^test"
      assert project.id != nil

      projects = Ash.read!(Project)
      assert length(projects) == 1
    end

    test "enforces unique name" do
      Ash.create!(Project, %{name: "test", pattern: "^test"})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(Project, %{name: "test", pattern: "^test2"})
      end
    end
  end

  describe "Session" do
    test "creates session with project" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      assert session.schema_version == 1
      assert session.transcript_dir == "test-dir"
    end
  end

  describe "Message" do
    test "creates message with session" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      message =
        Ash.create!(Message, %{
          uuid: "msg-1",
          type: :user,
          role: :user,
          timestamp: DateTime.utc_now(),
          session_id: session.id,
          content: %{"text" => "hello"}
        })

      assert message.type == :user
      assert message.content == %{"text" => "hello"}
    end
  end

  describe "Subagent" do
    test "creates subagent with session" do
      project = Ash.create!(Project, %{name: "test", pattern: "^test"})

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id
        })

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "abc123",
          session_id: session.id
        })

      assert subagent.agent_id == "abc123"
    end
  end
end
