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
      t.belongs_to :foo, polymorphic: true, :index => false # Rails5からindex:trueがデフォルトになっているため
    end

    create_table :blogs do |t|
      t.string :name
    end
  end
end

class User < ActiveRecord::Base
  has_many :articles
  has_one :article, :as => :foo
end

class Article < ActiveRecord::Base
  belongs_to :user
  belongs_to :foo, polymorphic: true
end

class Blog < ActiveRecord::Base
  has_many :sub_articles, :foreign_key => :foo_id
end

class SubArticle < Article
  belongs_to :blog, :class_name => "Blog", :foreign_key => :foo_id
end

Aam.logger = nil

if true
  require "i18n"
  I18n.enforce_available_locales = false
  I18n.default_locale = :ja
  I18n.backend.store_translations :ja, {:activerecord => {:models => {"sub_article" => "なんとか"} }, :attributes => {"user_id" => "ユーザー"}}
end

puts Aam::Generator.new(User).generate
puts Aam::Generator.new(Article).generate
puts Aam::Generator.new(Blog).generate
puts Aam::Generator.new(SubArticle).generate

# >> # == Schema Information ==
# >> #
# >> # User (users as User)
# >> #
# >> # |------+------+---------+-------------+------+-------|
# >> # | name | desc | type    | opts        | refs | index |
# >> # |------+------+---------+-------------+------+-------|
# >> # | id   | Id   | integer | NOT NULL PK |      |       |
# >> # | name | Name | string  |             |      | A!    |
# >> # | flag | Flag | boolean | DEFAULT(0)  |      |       |
# >> # |------+------+---------+-------------+------+-------|
# >> # == Schema Information ==
# >> #
# >> # Article (articles as Article)
# >> #
# >> # |----------+----------+---------+-------------+----------------------------+-------|
# >> # | name     | desc     | type    | opts        | refs                       | index |
# >> # |----------+----------+---------+-------------+----------------------------+-------|
# >> # | id       | Id       | integer | NOT NULL PK |                            |       |
# >> # | user_id  | ユーザー | integer |             | => User#id                 | A     |
# >> # | foo_type | Foo type | string  |             | SpecificModel(polymorphic) |       |
# >> # | foo_id   | Foo      | integer |             | => (foo_type)#id           |       |
# >> # |----------+----------+---------+-------------+----------------------------+-------|
# >> #
# >> # - Remarks ----------------------------------------------------------------------
# >> # User.has_many :articles
# >> # [Warning: Need to add index] create_articles マイグレーションに add_index :articles, [:foo_id, :foo_type] を追加してください
# >> # --------------------------------------------------------------------------------
# >> # == Schema Information ==
# >> #
# >> # Blog (blogs as Blog)
# >> #
# >> # |------+------+---------+-------------+------+-------|
# >> # | name | desc | type    | opts        | refs | index |
# >> # |------+------+---------+-------------+------+-------|
# >> # | id   | Id   | integer | NOT NULL PK |      |       |
# >> # | name | Name | string  |             |      |       |
# >> # |------+------+---------+-------------+------+-------|
# >> # == Schema Information ==
# >> #
# >> # なんとか (articles as SubArticle)
# >> #
# >> # |----------+----------+---------+-------------+--------------------------------------+-------|
# >> # | name     | desc     | type    | opts        | refs                                 | index |
# >> # |----------+----------+---------+-------------+--------------------------------------+-------|
# >> # | id       | Id       | integer | NOT NULL PK |                                      |       |
# >> # | user_id  | ユーザー | integer |             | => User#id                           | A     |
# >> # | foo_type | Foo type | string  |             | SpecificModel(polymorphic)           |       |
# >> # | foo_id   | Foo      | integer |             | :blog => Blog#id と => (foo_type)#id |       |
# >> # |----------+----------+---------+-------------+--------------------------------------+-------|
# >> #
# >> # - Remarks ----------------------------------------------------------------------
# >> # Blog.has_many :sub_articles, foreign_key: :foo_id
# >> # User.has_many :articles
# >> # [Warning: Need to add index] create_articles マイグレーションに add_index :articles, [:foo_id, :foo_type] を追加してください
# >> # --------------------------------------------------------------------------------
