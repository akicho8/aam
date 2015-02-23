# -*- coding: utf-8 -*-
require "bundler/setup"
Bundler.require

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
ActiveRecord::Schema.define do
  suppress_messages do
    create_table :users do |t|
      t.string :name
      t.boolean :flag, :default => false
    end
    add_index :users, :name, :unique => true

    create_table :articles do |t|
      t.belongs_to :user, index: true
      t.belongs_to :xxx, :polymorphic => true
    end

    create_table :blogs do |t|
      t.string :name
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

Aam.logger = nil

if true
  require "i18n"
  I18n.enforce_available_locales = false
  I18n.default_locale = :ja
  I18n.backend.store_translations :ja, {:activerecord => {:models => {"sub_article" => "なんとか"} }, :attributes => {"user_id" => "ユーザー"}}
end

puts Aam::SchemaInfoGenerator.new(SubArticle).generate
# >> # == Schema Information ==
# >> #
# >> # なんとかテーブル (articles)
# >> #
# >> # +----------+----------+---------+-------------+--------------------------------------+-------+
# >> # | カラム名 | 意味     | タイプ  | 属性        | 参照                                 | INDEX |
# >> # +----------+----------+---------+-------------+--------------------------------------+-------+
# >> # | id       | Id       | integer | NOT NULL PK |                                      |       |
# >> # | user_id  | ユーザー | integer |             | => User#id                           | A     |
# >> # | xxx_id   | Xxx      | integer |             | :blog => Blog#id と => (xxx_type)#id |       |
# >> # | xxx_type | Xxx type | string  |             | モデル名(polymorphic)                |       |
# >> # +----------+----------+---------+-------------+--------------------------------------+-------+
# >> #
# >> #- 警告 -------------------------------------------------------------------------
# >> # ・【警告:インデックス欠如】create_articles マイグレーションに add_index :articles, [:xxx_id, :xxx_type] を追加してください
# >> #--------------------------------------------------------------------------------
