# -*- coding: utf-8 -*-

require "rails"

desc "#{Rails.root} 以下のファイルに対してスキーマ情報を関連するファイルに書き込む"
task :aam => "aam:app"

namespace :aam do
  task :app => :environment do
    require "aam"
    Aam::Annotation.run
  end

  desc "#{Rails.root}/vendor/plugins 以下のファイルに対してスキーマ情報を関連するファイルに書き込む"
  task :plugins => :environment do
    require "aam"
    Aam::Annotation.run(:root_dir => Rails.root.join("vendor/plugins"))
  end
end
