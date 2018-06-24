$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "aam"

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
ActiveRecord::Schema.define do
  suppress_messages do
    create_table(:users) do |t|
      t.string :name, :limit => 32
      t.boolean :flag, :default => false
    end
    add_index :users, :name, :unique => true

    create_table(:articles) do |t|
      t.belongs_to :user, :index => false
      t.belongs_to :xxx, :polymorphic => true, :index => false
    end

    create_table(:blogs) do |t|
      t.string :name
    end

    create_table(:foos) do |t|
      t.belongs_to :user, :index => false
      t.belongs_to :xxx, :polymorphic => true, :index => false
    end
  end
end

class User < ActiveRecord::Base
  has_many :articles
  has_one :article, :as => :xxx
end

class Article < ActiveRecord::Base
  belongs_to :user
  belongs_to :xxx, :polymorphic => true
end

class Blog < ActiveRecord::Base
  has_many :sub_articles, :foreign_key => :xxx_id
end

class SubArticle < Article
  belongs_to :blog, :class_name => "Blog", :foreign_key => :xxx_id
end

class Foo < ActiveRecord::Base
end

Aam.logger = nil
puts Aam::SchemaInfoGenerator.new(User).generate
puts Aam::SchemaInfoGenerator.new(Article).generate
puts Aam::SchemaInfoGenerator.new(SubArticle).generate
puts Aam::SchemaInfoGenerator.new(Foo).generate
# >> # == Schema Information ==
# >> #
# >> # Userテーブル (users as User)
# >> #
# >> # |----------+------+------------+-------------+------+-------|
# >> # | カラム名 | 意味 | タイプ     | 属性        | 参照 | INDEX |
# >> # |----------+------+------------+-------------+------+-------|
# >> # | id       | Id   | integer    | NOT NULL PK |      |       |
# >> # | name     | Name | string(32) |             |      | A!    |
# >> # | flag     | Flag | boolean    | DEFAULT(f)  |      |       |
# >> # |----------+------+------------+-------------+------+-------|
# >> # == Schema Information ==
# >> #
# >> # Articleテーブル (articles as Article)
# >> #
# >> # |----------+----------+---------+-------------+-----------------------+-------|
# >> # | カラム名 | 意味     | タイプ  | 属性        | 参照                  | INDEX |
# >> # |----------+----------+---------+-------------+-----------------------+-------|
# >> # | id       | Id       | integer | NOT NULL PK |                       |       |
# >> # | user_id  | User     | integer |             | => User#id            |       |
# >> # | xxx_type | Xxx type | string  |             | モデル名(polymorphic) |       |
# >> # | xxx_id   | Xxx      | integer |             | => (xxx_type)#id      |       |
# >> # |----------+----------+---------+-------------+-----------------------+-------|
# >> #
# >> #- 備考 -------------------------------------------------------------------------
# >> # ・【警告:インデックス欠如】create_articles マイグレーションに add_index :articles, :user_id を追加してください
# >> # ・Article モデルは User モデルから has_many :articles されています。
# >> # ・【警告:インデックス欠如】create_articles マイグレーションに add_index :articles, [:xxx_id, :xxx_type] を追加してください
# >> #--------------------------------------------------------------------------------
# >> # == Schema Information ==
# >> #
# >> # Sub articleテーブル (articles as SubArticle)
# >> #
# >> # |----------+----------+---------+-------------+--------------------------------------+-------|
# >> # | カラム名 | 意味     | タイプ  | 属性        | 参照                                 | INDEX |
# >> # |----------+----------+---------+-------------+--------------------------------------+-------|
# >> # | id       | Id       | integer | NOT NULL PK |                                      |       |
# >> # | user_id  | User     | integer |             | => User#id                           |       |
# >> # | xxx_type | Xxx type | string  |             | モデル名(polymorphic)                |       |
# >> # | xxx_id   | Xxx      | integer |             | :blog => Blog#id と => (xxx_type)#id |       |
# >> # |----------+----------+---------+-------------+--------------------------------------+-------|
# >> #
# >> #- 備考 -------------------------------------------------------------------------
# >> # ・【警告:インデックス欠如】create_articles マイグレーションに add_index :articles, :user_id を追加してください
# >> # ・SubArticle モデルは User モデルから has_many :articles されています。
# >> # ・【警告:インデックス欠如】create_articles マイグレーションに add_index :articles, [:xxx_id, :xxx_type] を追加してください
# >> # ・SubArticle モデルは Blog モデルから has_many :sub_articles, :foreign_key => :xxx_id されています。
# >> #--------------------------------------------------------------------------------
# >> # == Schema Information ==
# >> #
# >> # Fooテーブル (foos as Foo)
# >> #
# >> # |----------+----------+---------+-------------+------+-------|
# >> # | カラム名 | 意味     | タイプ  | 属性        | 参照 | INDEX |
# >> # |----------+----------+---------+-------------+------+-------|
# >> # | id       | Id       | integer | NOT NULL PK |      |       |
# >> # | user_id  | User     | integer |             |      |       |
# >> # | xxx_type | Xxx type | string  |             |      |       |
# >> # | xxx_id   | Xxx      | integer |             |      |       |
# >> # |----------+----------+---------+-------------+------+-------|
# >> #
# >> #- 備考 -------------------------------------------------------------------------
# >> # ・【警告:インデックス欠如】create_foos マイグレーションに add_index :foos, :user_id を追加してください
# >> # ・【警告】Foo モデルに belongs_to :user を追加してください
# >> # ・【警告:インデックス欠如】create_foos マイグレーションに add_index :foos, [:xxx_id, :xxx_type] を追加してください
# >> # ・【警告】Foo モデルに belongs_to :xxx, :polymorphic => true を追加してください
# >> #--------------------------------------------------------------------------------
