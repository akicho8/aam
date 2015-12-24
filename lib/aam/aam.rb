# -*- coding: utf-8 -*-
#
# AnnotateModels(改)
#
# ・対象のディレクトリを変更できる
# ・カラムの日本語約付き
# ・コントローラーにも記入できる
# ・テストユニットにも記入できる
# ・リレーションされてないのを指摘

require "active_record"
require "active_support/core_ext/string/filters"
require "rain_table"

module Aam
  SCHEMA_HEADER = "# == Schema Information =="

  mattr_accessor :logger
  self.logger = ActiveSupport::Logger.new(STDOUT)

  class SchemaInfoGenerator
    def initialize(klass, options = {})
      @klass = klass
      @options = {
        :skip_columns => [],
      }.merge(options)
      @alerts = []
    end

    def generate
      rows = @klass.columns.collect {|column|
        next if @options[:skip_columns].include?(column.name)
        [
          column.name,
          column_to_human_name(column.name),
          column_type_inspect_of(column),
          column_attribute_inspect_of(column),
          reflections_inspect_of(column),
          index_info(column),
        ]
      }.compact
      out = []
      out << "#{SCHEMA_HEADER}\n#\n"
      out << "# #{@klass.model_name.human}テーブル (#{@klass.table_name})\n"
      out << "#\n"
      out << RainTable::TableFormatter.format(["カラム名", "意味", "タイプ", "属性", "参照", "INDEX"], rows).lines.collect{|row|"# #{row}"}.join
      if @alerts.present?
        out << "#\n"
        out << "#- 警告 -------------------------------------------------------------------------\n"
        out << @alerts.collect{|row|"# ・#{row}\n"}.join
        out << "#--------------------------------------------------------------------------------\n"
      end
      out.join
    end

    private

    def column_type_inspect_of(column)
      size = nil
      if column.type.to_s == "decimal"
        size = "(#{column.precision}, #{column.scale})"
      else
        if column.limit
          size = "(#{column.limit})"
        end
      end
      # シリアライズされているかチェック
      if serialized_klass = @klass.serialized_attributes[column.name] # FIXME: Rails5でなくなるらしい
        if serialized_klass.kind_of? ActiveRecord::Coders::YAMLColumn
          serialized_klass = "=> #{serialized_klass.object_class}"
        else
          serialized_klass = "=> #{serialized_klass}"
        end
      end
      "#{column.type}#{size} #{serialized_klass}".squish
    end

    def column_attribute_inspect_of(column)
      attrs = []
      unless column.default.nil?
        default = column.default
        if default.kind_of? BigDecimal
          default = default.to_f
          if default.zero?
            default = 0
          end
        end
        attrs << "DEFAULT(#{default})"
      end
      unless column.null
        attrs << "NOT NULL"
      end
      if column.name == @klass.primary_key
        attrs << "PK"
      end
      attrs * " "
    end

    def reflections_inspect_of(column)
      [reflections_inspect_ary_of(column)].flatten.compact.sort.join(" と ")
    end

    def reflections_inspect_ary_of(column)
      if column.name == @klass.inheritance_column             # カラムが "type" のとき
        return "モデル名(STI)"
      end

      index_check(column)

      my_refrections = @klass.reflections.find_all do |key, reflection|
        if !reflection.is_a?(ActiveRecord::Reflection::ThroughReflection) && reflection.respond_to?(:foreign_key)
          reflection.foreign_key.to_s == column.name
        end
      end

      if my_refrections.empty?
        # "xxx_id" は belongs_to されていることを確認
        if md = column.name.match(/(\w+)_id\z/)
          name = md.captures.first
          if @klass.column_names.include?("#{name}_type")
            syntax = "belongs_to :#{name}, :polymorphic => true"
          else
            syntax = "belongs_to :#{name}"
          end
          alert_puts "【警告】#{@klass} モデルに #{syntax} を追加してください"
        else
          # "xxx_type" は polymorphic 指定されていることを確認
          key, reflection = @klass.reflections.find do |key, reflection|
            _options = reflection.options
            if true
              # >= 3.1.3
              _options[:polymorphic] && column.name == "#{key}_type"
            else
              # < 3.1.3
              _options[:polymorphic] && _options[:foreign_type] == column.name
            end
          end
          if reflection
            "モデル名(polymorphic)"
          end
        end
      else
        # 一つのカラムを複数の方法で利用している場合に対応するため回している。
        my_refrections.collect do |key, reflection|
          begin
            reflection_inspect_of(column, reflection)
          rescue NameError => error
            puts "--------------------------------------------------------------------------------"
            puts "【警告】以下のクラスがないため NameError になっちゃってます"
            p error
            puts "--------------------------------------------------------------------------------"
          end
        end
      end
    end

    def reflection_inspect_of(column, reflection)
      return unless reflection.macro == :belongs_to
      desc = nil
      if reflection.options[:polymorphic]
        if true
          # >= 3.1.3
          target = "(#{reflection.name}_type)##{reflection.active_record.primary_key}"
        else
          # < 3.1.3
          target = "(#{reflection.options[:foreign_type]})##{reflection.active_record.primary_key}"
        end
      else
        target = "#{reflection.class_name}##{reflection.active_record.primary_key}"
        desc = belongs_to_model_has_many_syntax(column, reflection)
      end
      assoc_name = ""
      unless "#{reflection.name}_id" == column.name
        assoc_name = ":#{reflection.name}"
      end
      "#{assoc_name} => #{target} #{desc}".squish
    end

    # belongs_to :user している場合 User モデルから has_many :articles されていることを確認。
    #
    # 1. assoc_reflection.foreign_key.to_s == column.name という比較では foreign_key 指定されると不一致になるので注意すること。
    # と書いたけど不一致になってもよかった。これでリレーション正しく貼られてないと判断してよい。
    # 理由は belongs_to に foreign_key が指定されたら has_many 側も has_many :foos, :foreign_key => "bar_id" とならないといけないため。
    #
    def belongs_to_model_has_many_syntax(column, reflection)
      assoc_key, assoc_reflection = reflection.class_name.constantize.reflections.find do |assoc_key, assoc_reflection|
        if false
          r = reflection.class_name.constantize == assoc_reflection.active_record && [:has_many, :has_one].include?(assoc_reflection.macro)
        else
          r = assoc_reflection.respond_to?(:foreign_key) && assoc_reflection.foreign_key.to_s == column.name
        end
        if r
          syntax = ["#{assoc_reflection.macro} :#{assoc_reflection.name}"]
          if assoc_reflection.options[:foreign_key]
            syntax << ":foreign_key => :#{assoc_reflection.options[:foreign_key]}"
          end
          Aam.logger.debug "#{@klass.name} モデルは #{assoc_reflection.active_record} モデルから #{syntax.join(', ')} されています。" if Aam.logger
          r
        end
      end
      unless assoc_reflection
        syntax = ["has_many :#{@klass.name.underscore.pluralize}"]
        if false
          # has_many :sub_articles の場合デフォルトで SubArticle を見るため不要
          syntax << ":class_name => \"#{@klass.name}\""
        end
        if reflection.options[:foreign_key]
          syntax << ":foreign_key => :#{reflection.options[:foreign_key]}"
        end
        alert_puts "【警告:リレーション欠如】#{reflection.class_name}モデルで #{syntax.join(', ')} されていません"
      end
    end

    # カラム翻訳
    #
    #   ja.rb:
    #     :item => "アイテム"
    #
    #   実行結果:
    #     column_to_human_name("item")    #=> "アイテム"
    #     column_to_human_name("item_id") #=> "アイテムID"
    #
    def column_to_human_name(name)
      resp = nil
      suffixes = {
        :id => "ID",
        :type => "タイプ",
      }
      suffixes.each do |key, value|
        if md = name.match(/(?<name_without_suffix>\w+)_#{key}$/)
          # サフィックス付きのまま明示的に翻訳されている場合はそれを使う
          resp = @klass.human_attribute_name(name, :default => "").presence
          # サフィックスなしが明示的に翻訳されていたらそれを使う
          unless resp
            if v = @klass.human_attribute_name(md[:name_without_suffix], :default => "").presence
              resp = "#{v}#{value}"
            end
          end
        end
        if resp
          break
        end
      end
      # 翻訳が効いてないけどid付きのまま仕方なく変換する
      resp ||= @klass.human_attribute_name(name)
    end

    #
    # インデックス情報の取得
    #
    #   add_index :articles, :name                  #=> "I"
    #   add_index :articles, :name, :unique => true #=> "UI"
    #
    def index_info(column)
      indexes = @klass.connection.indexes(@klass.table_name)
      # 関係するインデックスに絞る
      indexes2 = indexes.find_all {|e| e.columns.include?(column.name) }
      indexes2.collect {|e|
        mark = ""
        # そのインデックスは何番目にあるかを調べる
        mark << ("A".."Z").to_a.at(indexes.index(e)).to_s
        # ユニークなら「！」
        if e.unique
          mark << "!"
        end
        # mark << e.columns.size.to_s # 1なら単独、2ならペア、3ならトリプル指定みたいなのわかる
        mark
      }.join(" ")
    end

    #
    # 指定のカラムは何かのインデックスに含まれているか？
    #
    def index_column?(column)
      indexes = @klass.connection.indexes(@klass.table_name)
      indexes.any?{|e|e.columns.include?(column.name)}
    end

    #
    # belongs_to のカラムか？
    #
    def belongs_to_column?(column)
      @klass.reflections.any? do |key, reflection|
        if reflection.macro == :belongs_to
          if reflection.respond_to?(:foreign_key)
            reflection.foreign_key.to_s == column.name
          end
        end
      end
    end

    #
    # 指定のカラムがインデックスを貼るべきかどうかを表示する
    #
    def index_check(column)
      if column.name.match(/(\w+)_id\z/) || belongs_to_column?(column)
        # belongs_to :xxx, :polymorphic => true の場合は xxx_id と xxx_type のペアでインデックスを貼る
        if (md = column.name.match(/(\w+)_id\z/)) && (type_column = @klass.columns_hash["#{md.captures.first}_type"])
          unless index_column?(column) && index_column?(type_column)
            alert_puts "【警告:インデックス欠如】create_#{@klass.table_name} マイグレーションに add_index :#{@klass.table_name}, [:#{column.name}, :#{type_column.name}] を追加してください"
          end
        else
          unless index_column?(column)
            alert_puts "【警告:インデックス欠如】create_#{@klass.table_name} マイグレーションに add_index :#{@klass.table_name}, :#{column.name} を追加してください"
          end
        end
      end
    end

    def alert_puts(str)
      Aam.logger.debug str if Aam.logger
      @alerts << str
      nil
    end
  end

  class Annotation
    MAGIC_COMMENT_LINE = "# -*- coding: utf-8 -*-\n"

    attr_accessor :counts, :options

    def self.run(options = {})
      new(options).run
    end

    def initialize(options = {})
      @options = {
        :root_dir => Rails.root,
        :dry_run => false,
        :skip_columns => [], # %w(id created_at updated_at),
        :models => ENV["MODEL"].presence || ENV["MODELS"].presence,
      }.merge(options)
      @counts = Hash.new(0)
      STDOUT.sync = true
    end

    def run
      target_ar_klasses.each do |klass|
        begin
          model = Model.new(self, klass)
          model.write_to_relation_files
        rescue ActiveRecord::ActiveRecordError => error
          puts "--------------------------------------------------------------------------------"
          p error
          puts "--------------------------------------------------------------------------------"
          @counts[:error] += 1
        end
      end
      puts "#{@counts[:success]} success, #{@counts[:skip]} skip, #{@counts[:error]} errors"
    end

    private

    class Model
      def initialize(base, klass)
        @base = base
        @klass = klass
      end

      def schema_info
        @schema_info ||= SchemaInfoGenerator.new(@klass, @base.options).generate + "\n"
      end

      def write_to_relation_files
        puts "--------------------------------------------------------------------------------"
        puts "--> #{@klass}"
        target_files = search_paths.collect {|search_path|
          Pathname.glob((@base.options[:root_dir] + search_path).expand_path)
        }.flatten.uniq
        target_files.each {|e| annotate_write(e) }
      end

      private

      # TODO: アプリの構成に依存しすぎ？
      def search_paths
        paths = []
        paths << "**/app/models/**/#{@klass.name.underscore}.rb"
        paths << "**/app/models/**/#{@klass.name.underscore}_{search,observer,callback,sweeper}.rb"
        paths << "**/test/unit/**/#{@klass.name.underscore}_test.rb"
        paths << "**/test/fixtures/**/#{@klass.name.underscore.pluralize}.yml"
        paths << "**/test/unit/helpers/**/#{@klass.name.underscore}_helper_test.rb"
        paths << "**/spec/models/**/#{@klass.name.underscore}_spec.rb"
        paths << "**/{test,spec}/**/#{@klass.name.underscore}_factory.rb"
        [:pluralize, :singularize].each{|method|
          prefix = @klass.name.underscore.send(method)
          [
            "**/app/controllers/**/#{prefix}_controller.rb",
            "**/app/helpers/**/#{prefix}_helper.rb",
            "**/test/functional/**/#{prefix}_controller_test.rb",
            "**/test/factories/**/#{prefix}_factory.rb",
            "**/test/factories/**/#{prefix}.rb",
            "**/db/seeds/**/{[0-9]*_,}#{prefix}_setup.rb",
            "**/db/seeds/**/{[0-9]*_,}#{prefix}_seed.rb",
            "**/db/seeds/**/{[0-9]*_,}#{prefix}.rb",
            "**/db/migrate/*_{create,to,from}_#{prefix}.rb",
            "**/spec/**/#{prefix}_{controller,helper}_spec.rb",
          ].each{|path|
            paths << path
            paths << "**/#{path}"
          }
        }
        paths
      end

      def annotate_write(file_name)
        body = file_name.read
        regexp = /^#{SCHEMA_HEADER}\n(#.*\n)*\n+/
        if body.match(regexp)
          body = body.sub(regexp, schema_info)
        elsif body.include?(MAGIC_COMMENT_LINE)
          body = body.sub(/#{Regexp.escape(MAGIC_COMMENT_LINE)}\s*/) {MAGIC_COMMENT_LINE + schema_info}
        else
          body = body.sub(/^\s*/, schema_info)
        end
        body = insert_magick_comment(body)
        unless @base.options[:dry_run]
          file_name.write(body)
        end
        puts "write: #{file_name}"
        @base.counts[:success] += 1
      end

      def insert_magick_comment(body, force = false)
        if force
          body = body.sub(/#{Regexp.escape(MAGIC_COMMENT_LINE)}\s*/, "")
        end
        unless body.include?(MAGIC_COMMENT_LINE)
          body = body.sub(/^\s*/, MAGIC_COMMENT_LINE)
        end
        body
      end
    end

    #
    # 対象のモデルファイル
    #
    def target_model_files
      files = []
      files += Pathname.glob("#{@options[:root_dir]}/app/models/**/*.rb")
      files += Pathname.glob("#{@options[:root_dir]}/vendor/plugins/*/app/models/**/*.rb")
      if @options[:models]
        @options[:models].split(",").collect { |m|
          files.find_all { |e|
            e.basename(".*").to_s.match(/#{m.camelize}|#{m.underscore}/i)
          }
        }.flatten.uniq
      else
        files
      end
    end

    #
    # テーブルを持っているクラスたち
    #
    def target_ar_klasses
      models = []
      target_model_files.each do |file|
        file = file.expand_path
        klass = nil
        if true
          class_name = file.basename(".*").to_s.camelize # classify だと boss が bos になってしまう
          begin
            klass = class_name.constantize
          rescue LoadError => error # LoadError は rescue nil では捕捉できないため
            puts "#{class_name} に対応するファイルは見つかりませんでした : #{error}"
          rescue
          end
        else
          klass = file.basename(".*").to_s.classify.constantize rescue nil
        end
        # klass.class == Class を入れないと [] < ActiveRecord::Base のときにエラーになる
        if klass && klass.class == Class && klass < ActiveRecord::Base && !klass.abstract_class?
          # puts "#{file} は ActiveRecord::Base のサブクラスなので対象とします。"
          puts "model: #{file}"
          models << klass
        else
          # puts "#{file} (クラス名:#{class_name}) は ActiveRecord::Base のサブクラスではありませんでした。"
        end
      end
      models
    end
  end
end
