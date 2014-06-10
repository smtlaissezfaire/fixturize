require 'mongo'
require 'yaml'
require 'set'

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
    attr_writer :database_version

    def database_version
      @database_version ||= 0
    end

    def reset_version!
      @database_version = nil
    end

    def collection_name
      "fixturize_#{database_version}_"
    end

    def collection
      if !database
        raise "Fixturize is not yet setup!  Make sure the database is set!"
      end

      database.collection(collection_name)
    end

    def clear_cache!
      database.collections.each do |c|
        if c.name == /fixturize_/
          c.drop
        end
      end
    end

    def instrument_database(collection_name, method_name, *args)
      collection.insert_aliased_from_fixturize({
        :type => INSTRUMENT_DATABASE,
        :name => current_instrumentation,
        :collection_name => collection_name.to_s,
        :method_name => method_name.to_s,
        :args => YAML.dump(args)
      })
    end

    def instrument_ivars(ivars, context)
      ivars.each do |ivar|
        obj = context.instance_variable_get(ivar)

        # TODO: Use duck typing?
        if defined?(MongoMapper) && obj.kind_of?(MongoMapper::Document)
          collection.insert_aliased_from_fixturize({
            :type => INSTRUMENT_IVARS,
            :name => current_instrumentation,
            :ivar => ivar,
            :model => obj.class.to_s,
            :id => obj.id
          })
        end
      end
    end

    def load_data_from(instrumentation)
      collection = database.collection(instrumentation['collection_name'])
      collection.send(instrumentation['method_name'], *YAML.load(instrumentation['args']))
    end

    def load_ivars_from(instrumentation, target_obj)
      ivar = instrumentation['ivar']
      model_str = instrumentation['model']
      id = instrumentation['id']

      model = Object.const_get(model_str)
      obj = model.find(id)
      target_obj.instance_variable_set(ivar, obj)
    end

    def refresh!(name = nil)
      if name
        collection.remove({ :name => name.to_s })
      else
        collection.drop()
      end
    end

    def fixturize(name = nil, &block)
      if !name && block.respond_to?(:source_location)
        # is this portable?
        name = block.source_location.join(":")
      end

      if !name
        raise "A name must be given to fixturize"
      end

      name = name.to_s
      self.current_instrumentation = name
      db_instrumentations = collection.find({ :name => name, :type => INSTRUMENT_DATABASE }).to_a

      if db_instrumentations.any?
        uninstall!

        db_instrumentations.each do |instrumentation|
          load_data_from(instrumentation)
        end

        ivar_instrumentations = collection.find({ :name => name, :type => INSTRUMENT_IVARS }).to_a

        if ivar_instrumentations.any?
          ivar_instrumentations.each do |instrumentation|
            load_ivars_from(instrumentation, caller_of_block(block))
          end
        end
      else
        safe_install(&block)
      end
    end

  private

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
              Fixturize.instrument_database(@name, :#{method_name}, *args, &block)
              #{method_name}_aliased_from_fixturize(*args, &block)
            end
          end
        HERE
      end

      block_caller = caller_of_block(block)
      ivars_before_block = block_caller.instance_variables

      yield.tap do
        new_ivars = (Set.new(block_caller.instance_variables) - Set.new(ivars_before_block)).to_a
        instrument_ivars(new_ivars, block_caller)
      end
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
