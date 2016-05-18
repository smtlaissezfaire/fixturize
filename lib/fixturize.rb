require 'mongo'
require 'yaml'
require 'set'
require 'method_source'
require 'digest/sha1'
require "redis"

class Fixturize
  METHODS_FOR_INSTRUMENTATION = [
    :save,
    :insert,
    :remove,
    :update,
    :drop,
    :rename,
  ]

  INSERT_TYPES = [
    INSTRUMENT_DATABASE = "instrument_database",
    INSTRUMENT_IVARS = "instrument_ivar"
  ]

  class << self
    attr_accessor :database
    attr_accessor :current_instrumentation
    attr_accessor :enabled
    attr_writer :database_version
    attr_accessor :relative_path_root

    ABSOLUTE_FIXTURIZE_PREFIX = "__fixturize_"

    def redis
      @redis ||= Redis.new
    end

    attr_writer :redis

    def enabled?
      enabled ? true : false
    end

    def database_version
      @database_version ||= 0
    end

    def reset_version!
      @database_version = nil
    end

    def prefix_key_name
      "#{ABSOLUTE_FIXTURIZE_PREFIX}#{database_version}"
    end

    def keys
      redis.keys("#{prefix_key_name}*")
    end

    def clear_cache!
      redis.keys("#{prefix_key_name}_*").each do |key|
        redis.del(key)
      end
    end

    def clear_old_versions!
      return unless enabled?

      redis.keys("#{ABSOLUTE_FIXTURIZE_PREFIX}*").each do |key|
        if key !~ /^#{prefix_key_name}/
          redis.del(key)
        end
      end
    end

    def refresh!(name = nil)
      return unless enabled?

      if name
        name = fixture_name(name)
        redis.del(name)
      else
        redis.keys("#{prefix_key_name}*").each do |key|
          redis.del(key)
        end
      end
    end

    def fixture_name(name = nil, &block)
      if !name && block.respond_to?(:source_location)
        # is this portable?
        file_name, line_number = block.source_location

        if relative_path_root && file_name.start_with?(relative_path_root)
          file_name = file_name[relative_path_root.length + 1 .. -1]
        end

        name = [file_name, line_number].join(":")

        if block.respond_to?(:source)
          name += ":" + Digest::SHA1.hexdigest(block.source.strip)
        end
      end

      if !name
        raise "A name must be given to fixturize"
      end

      "#{prefix_key_name}_#{name.to_s}"
    end

    def fixturize(name = nil, &block)
      raise LocalJumpError.new("fixturize requires a block") unless block_given?
      return yield if !enabled?

      name = fixture_name(name, &block)
      self.current_instrumentation = name

      all_instrumentations = redis.lrange(current_instrumentation, 0, -1)
      all_instrumentations.map! { |inst| Marshal.load(inst) }

      db_instrumentations = all_instrumentations.select { |i| i[:type] == INSTRUMENT_DATABASE }

      if db_instrumentations.any?
        uninstall!

        db_instrumentations.each do |instrumentation|
          load_data_from(instrumentation)
        end

        ivar_instrumentations = all_instrumentations.select { |i| i[:type] == INSTRUMENT_IVARS }

        if ivar_instrumentations.any?
          ivar_instrumentations.each do |instrumentation|
            load_ivars_from(instrumentation, caller_of_block(block))
          end
        end
      else
        safe_install(&block)
      end
    end

    def _instrument_database(collection_name, method_name, *args)
      redis.rpush(current_instrumentation, Marshal.dump({
        :type => INSTRUMENT_DATABASE,
        :name => current_instrumentation,
        :collection_name => collection_name.to_s,
        :method_name => method_name.to_s,
        :args => args,
        :timestamp => Time.now.to_f
      }))
    end

  private

    def instrument_ivars(ivars, context)
      ivars.each do |ivar|
        obj = context.instance_variable_get(ivar)

        # TODO: Use duck typing?
        if defined?(MongoMapper) && obj.kind_of?(MongoMapper::Document)
          redis.rpush(current_instrumentation, Marshal.dump({
            :type => INSTRUMENT_IVARS,
            :name => current_instrumentation,
            :ivar => ivar,
            :model => obj.class.to_s,
            :id => obj.id,
            :timestamp => Time.now.to_f
          }))
        end
      end
    end

    def load_data_from(instrumentation)
      collection = database.collection(instrumentation[:collection_name])
      collection.send(instrumentation[:method_name], *instrumentation[:args])
    end

    def load_ivars_from(instrumentation, target_obj)
      ivar = instrumentation[:ivar]
      model_str = instrumentation[:model]
      id = instrumentation[:id]

      model = Object.const_get(model_str)
      obj = model.find(id)
      target_obj.instance_variable_set(ivar, obj)
    end

    def caller_of_block(block)
      block.binding.eval("self")
    end

    def safe_install(&block)
      install!(&block)
    ensure
      self.current_instrumentation = nil
      uninstall!
    end

    def install!(&block)
      METHODS_FOR_INSTRUMENTATION.each do |method_name|
        Mongo::Collection.class_eval <<-HERE, __FILE__, __LINE__
          unless instance_methods.include?(:#{method_name}_aliased_from_fixturize)
            alias_method :#{method_name}_aliased_from_fixturize, :#{method_name}

            def #{method_name}(*args, &block)
              Fixturize._instrument_database(@name, :#{method_name}, *args, &block)
              #{method_name}_aliased_from_fixturize(*args, &block)
            end
          end
        HERE
      end

      block_caller = caller_of_block(block)

      begin
        ret_val = yield
      rescue => e
        redis.del(current_instrumentation)
        raise e
      end

      instrument_ivars(block_caller.instance_variables, block_caller)
      ret_val
    end

    def uninstall!
      METHODS_FOR_INSTRUMENTATION.each do |method_name|
        Mongo::Collection.class_eval <<-HERE, __FILE__, __LINE__
          if instance_methods.include?(:#{method_name}_aliased_from_fixturize)
            alias_method :#{method_name}, :#{method_name}_aliased_from_fixturize
            remove_method :#{method_name}_aliased_from_fixturize
          end
        HERE
      end
    end
  end
end

def fixturize(*args, &block)
  Fixturize.fixturize(*args, &block)
end

if defined?(MongoMapper && MongoMapper.database)
  Fixturize.database = MongoMapper.database
end
