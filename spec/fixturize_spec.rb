require 'spec_helper'

describe Fixturize do
  before do
    @db = MongoMapper.database

    @users = @db.collection('users_for_mongo_saved_contexts')

    @context = Fixturize
    @context.database = @db
    @context.refresh!
    @context.reset_version!
  end

  it "should be able to take a block (and do nothing)" do
    lambda {
      @context.fixturize "some name" do
      end
    }.should_not raise_error
  end

  it "should be able to fixturize some data" do
    @context.fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.drop()

    @context.fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.count().should == 1
  end

  it "should not run the block the second time around" do
    @context.fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.drop()

    @block_run = false

    @context.fixturize "insert users" do
      @block_run = true
      @users.insert({ :first_name => "Scott" })
    end

    @block_run.should == false
  end

  it "should return the value of the block when newly created" do
    val = @context.fixturize "foo" do
      1
    end

    val.should == 1
  end

  it "should work with an update" do
    @users.insert({ :first_name => "Scott" })

    @context.fixturize "change name" do
      @users.update({}, { :last_name => "Taylor" })
    end

    @users.drop()

    @users.insert({ :first_name => "Scott" })
    @context.fixturize "change name"

    @users.find().to_a[0]['last_name'].should == "Taylor"
  end

  it "should be able to remove the updates for all contexts" do
    @context.fixturize "insert user" do
      @users.insert({ :first_name => "First Name" })
    end

    @users.drop()

    @context.refresh!

    block_run = false

    @context.fixturize "insert user" do
      @users.insert({ :first_name => "Scott" })
      block_run = true
    end

    @users.count().should == 1
    @users.find().to_a[0]["first_name"].should == "Scott"
    block_run.should == true
  end

  it "should be able to just reload one fixturized block" do
    @context.fixturize "insert user" do
      @users.insert({ :first_name => "Scott" })
    end
    @context.fixturize "update user" do
      @users.update({ :first_name => "Scott" }, { :last_name => "Taylor" })
    end

    @users.drop()

    @context.refresh!("update user")

    @context.fixturize "insert user"
    @context.fixturize "update user" do
      @users.update({ :first_name => "Scott" }, { :last_name => "Baylor" })
    end

    @users.count().should == 1
    @users.find().to_a[0]["last_name"].should == "Baylor"
  end

  it "should be at version 0 by default" do
    @context.database_version.should == 0
  end

  it "should be able to bump the version" do
    @context.database_version = 1
    @context.database_version.should == 1
  end

  it "should use the version number in the database table name" do
    @context.collection_name.should == "mongo_saved_contexts_0_"

    @context.database_version = 99
    @context.collection_name.should == "mongo_saved_contexts_99_"
  end

  it "should have a list of all the collections it uses" do
    @context.collections.should == ["mongo_saved_contexts_0_"]
  end
end