require 'spec_helper'

describe Fixturize do
  before do
    @db = MongoMapper.database

    @users = @db.collection('users_for_mongo_saved_contexts')

    Fixturize.database = @db
    Fixturize.refresh!
    Fixturize.reset_version!
  end

  it "should be able to take a block (and do nothing)" do
    lambda {
      fixturize "some name" do
      end
    }.should_not raise_error
  end

  it "should be able to fixturize some data" do
    fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.drop()

    fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.count().should == 1
  end

  it "should not run the block the second time around" do
    fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.drop()

    @block_run = false

    fixturize "insert users" do
      @block_run = true
      @users.insert({ :first_name => "Scott" })
    end

    @block_run.should == false
  end

  it "should return the value of the block when newly created" do
    val = fixturize "foo" do
      1
    end

    val.should == 1
  end

  it "should work with an update" do
    @users.insert({ :first_name => "Scott" })

    fixturize "change name" do
      @users.update({}, { :last_name => "Taylor" })
    end

    @users.drop()

    @users.insert({ :first_name => "Scott" })
    fixturize "change name"

    @users.find().to_a[0]['last_name'].should == "Taylor"
  end

  it "should be able to remove the updates for all contexts" do
    fixturize "insert user" do
      @users.insert({ :first_name => "First Name" })
    end

    @users.drop()

    Fixturize.refresh!

    block_run = false

    fixturize "insert user" do
      @users.insert({ :first_name => "Scott" })
      block_run = true
    end

    @users.count().should == 1
    @users.find().to_a[0]["first_name"].should == "Scott"
    block_run.should == true
  end

  it "should be able to just reload one fixturized block" do
    fixturize "insert user" do
      @users.insert({ :first_name => "Scott" })
    end
    fixturize "update user" do
      @users.update({ :first_name => "Scott" }, { :last_name => "Taylor" })
    end

    @users.drop()

    Fixturize.refresh!("update user")

    fixturize "insert user"
    fixturize "update user" do
      @users.update({ :first_name => "Scott" }, { :last_name => "Baylor" })
    end

    @users.count().should == 1
    @users.find().to_a[0]["last_name"].should == "Baylor"
  end

  it "should be at version 0 by default" do
    Fixturize.database_version.should == 0
  end

  it "should be able to bump the version" do
    Fixturize.database_version = 1
    Fixturize.database_version.should == 1
  end

  it "should use the version number in the database table name" do
    Fixturize.db_updates_collection_name.should == "mongo_saved_contexts_0_"

    Fixturize.database_version = 99
    Fixturize.db_updates_collection_name.should == "mongo_saved_contexts_99_"
  end

  it "should have a list of all the collections it uses" do
    Fixturize.collections.should == ["mongo_saved_contexts_0_"]
  end
end