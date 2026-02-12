defmodule Spotter.Transcripts.CoChangeGroupCommit do
  @moduledoc "Links a co-change group to a relevant commit that contained all group members."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "co_change_group_commits"
    repo Spotter.Repo
  end

  json_api do
    type "co_change_group_commit"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :scope,
        :group_key,
        :commit_hash,
        :committed_at,
        :project_id
      ]

      upsert? true
      upsert_identity :unique_group_commit
      upsert_fields [:committed_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :scope, :atom do
      allow_nil? false
      constraints one_of: [:file, :directory]
    end

    attribute :group_key, :string, allow_nil?: false
    attribute :commit_hash, :string, allow_nil?: false
    attribute :committed_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_group_commit, [:project_id, :scope, :group_key, :commit_hash]
  end
end
