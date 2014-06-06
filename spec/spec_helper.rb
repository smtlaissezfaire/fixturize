require 'rubygems'
require 'rspec'
require 'mongo_mapper'

MongoMapper.connection = Mongo::Connection.new('localhost')
MongoMapper.database = "fixturize"

require File.join(File.dirname(__FILE__), '..', 'lib', 'fixturize')

RSpec.configure do |config|
  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = "random"

  def wipe_db
    MongoMapper.database.collections.each do |c|
      unless (c.name =~ /system/ || Fixturize.collections.include?(c.name))
        c.drop()
      end
    end
  end

  config.before(:each) do
    wipe_db
  end
end