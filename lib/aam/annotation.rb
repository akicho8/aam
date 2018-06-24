module Aam
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
      schema_info_text_write
      puts
      model_file_write_all
    end

    def model_file_write_all
      target_ar_klasses_from_model_filenames.each do |klass|
        begin
          model = Model.new(self, klass)
          model.write_to_relation_files
        rescue ActiveRecord::ActiveRecordError => error
          if @options[:debug]
            puts "--------------------------------------------------------------------------------"
            p error
            puts "--------------------------------------------------------------------------------"
          end
          @counts[:error] += 1
        end
      end
      puts "#{@counts[:success]} success, #{@counts[:skip]} skip, #{@counts[:error]} errors"
    end

    def schema_info_text_write
      @all = []
      target_ar_klasses_from_model_require_and_ar_subclasses.each do |klass|
        begin
          model = Model.new(self, klass)
          @all << model.schema_info
        rescue ActiveRecord::ActiveRecordError => error
        end
      end
      file = options[:root_dir].join("db", "schema_info.txt")
      magic_comment = "-*- truncate-lines: t -*-"
      file.write("#{magic_comment}\n\n#{@all.join}")
      puts "output: #{file} (#{@all.size} counts)"
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
          v = Pathname.glob((@base.options[:root_dir] + search_path).expand_path)
          v.reject{|e|e.to_s.include?("node_modules")}
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
    # テーブルを持っているクラスたち
    #
    def target_ar_klasses
      target_ar_klasses_from_model_require_and_ar_subclasses
      # ActiveRecord::Base.subclasses
    end

    # すべての app/models/**/*.rb を require したあと ActiveRecord::Base.subclasses を参照
    def target_ar_klasses_from_model_require_and_ar_subclasses
      target_model_files.each do |file|
        begin
          silence_warnings do
            require file
          end
          puts "require: #{file}"
        rescue Exception
        end
      end
      if defined?(ApplicationRecord)
        ApplicationRecord.subclasses
      else
        ActiveRecord::Base.subclasses
      end
    end

    # app/models/* のファイル名を constantize してみることでクラスを収集する
    def target_ar_klasses_from_model_filenames
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
  end
end
