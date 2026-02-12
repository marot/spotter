defmodule Spotter.Transcripts.CoChangeGroupMemberStat do
  @moduledoc "Per-member file metrics for a co-change group, measured at a specific commit."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "co_change_group_member_stats"
    repo Spotter.Repo
  end

  json_api do
    type "co_change_group_member_stat"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :scope,
        :group_key,
        :member_path,
        :size_bytes,
        :loc,
        :measured_commit_hash,
        :measured_at,
        :project_id
      ]

      upsert? true
      upsert_identity :unique_group_member_stat
      upsert_fields [:size_bytes, :loc, :measured_commit_hash, :measured_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :scope, :atom do
      allow_nil? false
      constraints one_of: [:file, :directory]
    end

    attribute :group_key, :string, allow_nil?: false
    attribute :member_path, :string, allow_nil?: false
    attribute :size_bytes, :integer
    attribute :loc, :integer
    attribute :measured_commit_hash, :string
    attribute :measured_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_group_member_stat, [:project_id, :scope, :group_key, :member_path]
  end
end
