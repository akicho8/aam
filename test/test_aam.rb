# -*- coding: utf-8 -*-
require 'test_helper'

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
      t.belongs_to :xxx, polymorphic: true, :index => false
    end
    create_table(:blogs) do |t|
      t.string :name
    end
    create_table(:foos) do |t|
      t.belongs_to :user, :index => false
      t.belongs_to :xxx, polymorphic: true, :index => false
    end
  end
end

class User < ActiveRecord::Base
  has_many :articles
  has_one :article, :as => :xxx
end

class Article < ActiveRecord::Base
  belongs_to :user
  belongs_to :xxx, polymorphic: true
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

class TestAam < Test::Unit::TestCase
  test "test_main" do
    assert_equal <<-EOT.strip_heredoc, Aam::Generator.new(User).generate
# == Schema Information ==
#
# User (users as User)
#
# |------+------+------------+-------------+------+-------|
# | name | desc | type       | opts        | refs | index |
# |------+------+------------+-------------+------+-------|
# | id   | Id   | integer    | NOT NULL PK |      |       |
# | name | Name | string(32) |             |      | A!    |
# | flag | Flag | boolean    | DEFAULT(0)  |      |       |
# |------+------+------------+-------------+------+-------|
EOT
    assert_equal <<-EOT.strip_heredoc, Aam::Generator.new(Article).generate
# == Schema Information ==
#
# Article (articles as Article)
#
# |----------+----------+---------+-------------+----------------------------+-------|
# | name     | desc     | type    | opts        | refs                       | index |
# |----------+----------+---------+-------------+----------------------------+-------|
# | id       | Id       | integer | NOT NULL PK |                            |       |
# | user_id  | User     | integer |             | => User#id                 |       |
# | xxx_type | Xxx type | string  |             | SpecificModel(polymorphic) |       |
# | xxx_id   | Xxx      | integer |             | => (xxx_type)#id           |       |
# |----------+----------+---------+-------------+----------------------------+-------|
#
# - Remarks ----------------------------------------------------------------------
# User.has_many :articles
# [Warning: Need to add index] create_articles マイグレーションに add_index :articles, :user_id を追加してください
# [Warning: Need to add index] create_articles マイグレーションに add_index :articles, [:xxx_id, :xxx_type] を追加してください
# --------------------------------------------------------------------------------
EOT
    Aam::Generator.new(SubArticle).generate == <<-EOT.strip_heredoc
# == Schema Information ==
#
# Sub article (articles as SubArticle)
#
# |----------+----------+---------+-------------+--------------------------------------+-------|
# | name     | desc     | type    | opts        | refs                                 | index |
# |----------+----------+---------+-------------+--------------------------------------+-------|
# | id       | Id       | integer | NOT NULL PK |                                      |       |
# | user_id  | User     | integer |             | => User#id                           |       |
# | xxx_type | Xxx type | string  |             | SpecificModel(polymorphic)           |       |
# | xxx_id   | Xxx      | integer |             | :blog => Blog#id と => (xxx_type)#id |       |
# |----------+----------+---------+-------------+--------------------------------------+-------|
#
# - 備考 -------------------------------------------------------------------------
# ・[Warning: Need to add index] create_articles マイグレーションに add_index :articles, :user_id を追加してください
# ・[Warning: Need to add index] create_articles マイグレーションに add_index :articles, [:xxx_id, :xxx_type] を追加してください
# --------------------------------------------------------------------------------
EOT
  end

  test "test_blog_sub_articles" do
    b = Blog.new
    b.sub_articles.build
    b.save!

    b.reload
    # p b.sub_articles
  end

  test "test_blog_sub_articles2" do
    b = Blog.new
    b.sub_articles.build
    b.save!

    b.reload
    # p b.sub_articles
  end

  test "test_foo" do
    assert_equal <<-EOT.strip_heredoc, Aam::Generator.new(Foo).generate
# == Schema Information ==
#
# Foo (foos as Foo)
#
# |----------+----------+---------+-------------+------+-------|
# | name     | desc     | type    | opts        | refs | index |
# |----------+----------+---------+-------------+------+-------|
# | id       | Id       | integer | NOT NULL PK |      |       |
# | user_id  | User     | integer |             |      |       |
# | xxx_type | Xxx type | string  |             |      |       |
# | xxx_id   | Xxx      | integer |             |      |       |
# |----------+----------+---------+-------------+------+-------|
#
# - Remarks ----------------------------------------------------------------------
# [Warning: Need to add index] create_foos マイグレーションに add_index :foos, :user_id を追加してください
# [Warning: Need to add index] create_foos マイグレーションに add_index :foos, [:xxx_id, :xxx_type] を追加してください
# [Warning: Need to add relation] Foo モデルに belongs_to :user を追加してください
# [Warning: Need to add relation] Foo モデルに belongs_to :xxx, polymorphic: true を追加してください
# --------------------------------------------------------------------------------
EOT
  end
end
