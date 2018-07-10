require "active_record"
require "active_support/core_ext/string/filters"
require "table_format"

module Aam
  class Generator
    def initialize(klass, options = {})
      @klass = klass
      @options = {
        :skip_columns => [],
        :debug => false,
      }.merge(options)
      @memos = []
    end

    def generate
      columns = @klass.columns.reject { |e|
        @options[:skip_columns].include?(e.name)
      }
      rows = columns.collect {|e|
        {
          "name"  => e.name,
          "desc"  => column_to_human_name(e.name),
          "type"  => column_type_inspect_of(e),
          "opts"  => column_attribute_inspect_of(e),
          "refs"  => reflections_inspect_of(e),
          "index" => index_info(e),
        }
      }
      out = []
      out << "#{SCHEMA_HEADER}\n#\n"
      out << "# #{@klass.model_name.human} (#{@klass.table_name} as #{@klass.name})\n"
      out << "#\n"
      out << rows.to_t.lines.collect { |e| "# #{e}" }.join
      if @memos.present?
        out << "#\n"
        out << "#- Remarks ----------------------------------------------------------------------\n"
        out << @memos.sort.collect{|row|"# #{row}\n"}.join
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
      serialized_klass = nil
      if @klass.respond_to?(:serialized_attributes) # Rails5 から無くなったため存在チェック
        if serialized_klass = @klass.serialized_attributes[column.name]
          if serialized_klass.kind_of? ActiveRecord::Coders::YAMLColumn
            serialized_klass = "=> #{serialized_klass.object_class}"
          else
            serialized_klass = "=> #{serialized_klass}"
          end
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
        return "SpecificModel(STI)"
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
            syntax = "belongs_to :#{name}, polymorphic: true"
          else
            syntax = "belongs_to :#{name}"
          end
          memo_puts "[Warning: Need to add relation] #{@klass} モデルに #{syntax} を追加してください"
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
            "SpecificModel(polymorphic)"
          end
        end
      else
        # 一つのカラムを複数の方法で利用している場合に対応するため回している。
        my_refrections.collect do |key, reflection|
          begin
            reflection_inspect_of(column, reflection)
          rescue NameError => error
            if @options[:debug]
              puts "--------------------------------------------------------------------------------"
              puts "【警告】以下のクラスがないため NameError になっちゃってます"
              p error
              puts "--------------------------------------------------------------------------------"
            end
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
            syntax << "foreign_key: :#{assoc_reflection.options[:foreign_key]}"
          end
          # memo_puts "#{@klass.name} モデルは #{assoc_reflection.active_record} モデルから #{syntax.join(', ')} されています。"
          memo_puts "#{assoc_reflection.active_record}.#{syntax.join(', ')}"
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
        memo_puts "【警告:リレーション欠如】#{reflection.class_name}モデルで #{syntax.join(', ')} されていません"
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
        # belongs_to :xxx, polymorphic: true の場合は xxx_id と xxx_type のペアでインデックスを貼る
        if (md = column.name.match(/(\w+)_id\z/)) && (type_column = @klass.columns_hash["#{md.captures.first}_type"])
          unless index_column?(column) && index_column?(type_column)
            memo_puts "[Warning: Need to add index] create_#{@klass.table_name} マイグレーションに add_index :#{@klass.table_name}, [:#{column.name}, :#{type_column.name}] を追加してください"
          end
        else
          unless index_column?(column)
            memo_puts "[Warning: Need to add index] create_#{@klass.table_name} マイグレーションに add_index :#{@klass.table_name}, :#{column.name} を追加してください"
          end
        end
      end
    end

    def memo_puts(str)
      if @options[:debug]
        Aam.logger.debug str if Aam.logger
      end
      @memos << str
      nil
    end
  end
end
