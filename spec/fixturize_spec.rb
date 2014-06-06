require 'spec_helper'

class User
  include MongoMapper::Document

  key :first_name, String
  key :last_name, String
end

describe Fixturize do
  before do
    @db = MongoMapper.database

    @users = @db.collection('users_for_mongo_saved_contexts')

    Fixturize.database = @db
    Fixturize.refresh!
    Fixturize.reset_version!
  end

  it "should be able to take a block (and do nothing)" do
    expect {
      fixturize "some name" do
      end
    }.to_not raise_error
  end

  it "should be able to fixturize some data" do
    fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.drop()

    fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    expect(@users.count()).to eq(1)
  end

  it "should not run the block the second time around" do
    fixturize "insert users" do
      @users.insert({ :first_name => "Scott" })
    end

    @users.drop()

    block_run = false

    fixturize "insert users" do
      block_run = true
      @users.insert({ :first_name => "Scott" })
    end

    expect(block_run).to eq(false)
  end

  it "should return the value of the block when newly created" do
    val = fixturize "foo" do
      1
    end

    expect(val).to eq(1)
  end

  it "should work with an update" do
    @users.insert({ :first_name => "Scott" })

    fixturize "change name" do
      @users.update({}, { :last_name => "Taylor" })
    end

    @users.drop()

    @users.insert({ :first_name => "Scott" })
    fixturize "change name"

    expect(@users.find().to_a[0]['last_name']).to eq("Taylor")
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

    expect(@users.count()).to eq(1)
    expect(@users.find().to_a[0]["first_name"]).to eq("Scott")
    expect(block_run).to eq(true)
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

    expect(@users.count()).to eq(1)
    expect(@users.find().to_a[0]["last_name"]).to eq("Baylor")
  end

  it "should be at version 0 by default" do
    expect(Fixturize.database_version).to eq(0)
  end

  it "should be able to bump the version" do
    Fixturize.database_version = 1
    expect(Fixturize.database_version).to eq(1)
  end

  it "should use the version number in the database table name" do
    expect(Fixturize.db_updates_collection_name).to eq("mongo_saved_contexts_0_")

    Fixturize.database_version = 99
    expect(Fixturize.db_updates_collection_name).to eq("mongo_saved_contexts_99_")
  end

  it "should have a list of all the collections it uses" do
    expect(Fixturize.collections).to eq(["mongo_saved_contexts_0_", "mongo_saved_ivars_0_"])
  end

  describe "with ivars" do
    it "should have access to ivars" do
      fixturize do
        @user = User.create!(:first_name => "Scott")
      end

      expect(@user.class).to eq(User)
      expect(@user.first_name).to eq("Scott")
    end

    it "should have access to ivars even when it is cached" do
      fixturize "creating scott" do
        @user = User.create!(:first_name => "Scott")
      end

      @user.destroy # must delete the data so we don't get invalid keys in mongo
      @user = nil
      block_run = false

      fixturize "creating scott" do
        block_run = true
        @user = User.create!(:first_name => "Scott")
      end

      expect(block_run).to eq(false)
      expect(@user).to_not eq(nil)
      expect(@user.class).to eq(User)
      expect(@user.first_name).to eq("Scott")
    end

    it "should be able to access many ivars" do
      fixturize "creating composers" do
        @bach = User.create!(:first_name => "Johann")
        @beethoven = User.create!(:first_name => "Ludwig")
      end

      @bach.destroy
      @beethoven.destroy
      @bach = nil
      @beethoven = nil
      block_run = false

      fixturize "creating composers" do
        block_run = true
      end

      expect(block_run).to eq(false)
      expect(@bach).to_not eq(nil)
      expect(@bach.class).to eq(User)
      expect(@bach.first_name).to eq("Johann")
      expect(@beethoven).to_not eq(nil)
      expect(@beethoven.class).to eq(User)
      expect(@beethoven.first_name).to eq("Ludwig")
    end

  end
end