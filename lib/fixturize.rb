require 'mongo'
require 'yaml'

class Fixturize
  METHODS_FOR_INSTRUMENTATION = [
    :save,
    :insert,
    :remove,
    :update,
    :drop,
    :rename,
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

    def collections
      [collection_name]
    end

    def collection_name
      "mongo_saved_contexts_#{database_version}_"
    end

    def clear_cache!
      MongoMapper.database.collections.each do |c|
        if c.name == /mongo_saved_contexts_/
          c.drop
        end
      end
    end

    def instrument(collection_name, method_name, *args)
      saved_contexts_collection.insert_aliased_from_mongo_saved_context({
        :name => current_instrumentation,
        :collection_name => collection_name.to_s,
        :method_name => method_name.to_s,
        :args => YAML.dump(args)
      })
    end

    def saved_contexts_collection
      if database
        database.collection(collection_name)
      else
        raise "Fixturize is not yet setup!  Make sure the database is set!"
      end
    end

    def refresh!(name = nil)
      if name
        saved_contexts_collection.remove({ :name => name.to_s })
      else
        saved_contexts_collection.drop()
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
      instrumentations = saved_contexts_collection.find({ :name => name }).to_a

      if instrumentations.any?
        uninstall!

        instrumentations.each do |instrumentation|
          collection = database.collection(instrumentation['collection_name'])
          collection.send(instrumentation['method_name'], *YAML.load(instrumentation['args']))
        end
      else
        begin
          install!
          yield
        ensure
          self.current_instrumentation = nil
          uninstall!
        end
      end
    end

  private

    def install!
      METHODS_FOR_INSTRUMENTATION.each do |method_name|
        Mongo::Collection.class_eval <<-HERE, __FILE__, __LINE__
          unless instance_methods.include?(:#{method_name}_aliased_from_mongo_saved_context)
            alias_method :#{method_name}_aliased_from_mongo_saved_context, :#{method_name}

            def #{method_name}(*args, &block)
              Fixturize.instrument(@name, :#{method_name}, *args, &block)
              #{method_name}_aliased_from_mongo_saved_context(*args, &block)
            end
          end
        HERE
      end
    end

    def uninstall!
      METHODS_FOR_INSTRUMENTATION.each do |method_name|
        Mongo::Collection.class_eval <<-HERE, __FILE__, __LINE__
          if instance_methods.include?(:#{method_name}_aliased_from_mongo_saved_context)
            alias_method :#{method_name}, :#{method_name}_aliased_from_mongo_saved_context
            remove_method :#{method_name}_aliased_from_mongo_saved_context
          end
        HERE
      end
    end
  end
end

if defined?(MongoMapper && MongoMapper.database)
  Fixturize.database = MongoMapper.database
end
