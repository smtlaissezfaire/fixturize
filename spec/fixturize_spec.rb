require 'spec_helper'

class User
  include MongoMapper::Document

  set_collection_name 'users_for_fixturize'

  key :first_name, String
  key :last_name, String
end

describe Fixturize do
  before do
    @db = MongoMapper.database

    @users = @db.collection('users_for_fixturize')

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

  it "should raise an error if no block is given" do
    expect {
      fixturize "some name"
    }.to raise_error(LocalJumpError)
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
    fixturize "change name" do; end

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

    fixturize "insert user" do; end
    fixturize "update user" do
      @users.update({ :first_name => "Scott" }, { :last_name => "Baylor" })
    end

    expect(@users.count()).to eq(1)
    expect(@users.find().to_a[0]["last_name"]).to eq("Baylor")
  end

  it "should not insert into the fixturized collection when reloading a block" do
    fixturize "one" do
      @users.insert(:first_name => "Scott")
    end

    old_count = Fixturize.collection.count

    fixturize "one" do
      @users.insert(:first_name => "Scott")
    end

    new_count = Fixturize.collection.count
    expect(new_count).to eq(old_count)
  end

  it "should be at version 0 by default" do
    expect(Fixturize.database_version).to eq(0)
  end

  it "should be able to bump the version" do
    Fixturize.database_version = 1
    expect(Fixturize.database_version).to eq(1)
  end

  it "should use the version number in the database table name" do
    expect(Fixturize.collection_name).to eq("fixturize_0_")

    Fixturize.database_version = 99
    expect(Fixturize.collection_name).to eq("fixturize_99_")
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

    it "should use the raw insert when inserting ivars" do
      fixturize "should use raw insert" do
        @user = User.create(:first_name => "Andrew 1")
      end

      old_count = Fixturize.collection.count

      @user.destroy

      fixturize "should use raw insert" do
        @user = User.create(:first_name => "Andrew")
      end

      new_count = Fixturize.collection.count

      expect(new_count).to eq(old_count)
    end
  end

  describe "when enabled" do
    before :each do
      Fixturize.enabled = true
    end

    it "should not run the block a second time" do
      fixturize "with enabled = false" do
        @users.insert(:first_name => "Scott")
      end

      expect(@users.count).to eq(1)

      @users.remove()
      block_run = false

      fixturize "with enabled = false" do
        block_run = true
        @users.insert(:first_name => "Scott")
      end
      expect(block_run).to eq(false)
      expect(@users.count).to eq(1)
    end
  end

  describe "when not enabled" do
    before :each do
      Fixturize.enabled = false
    end

    it "should always run a block" do
      fixturize "with enabled = false" do
        @users.insert(:first_name => "Scott")
      end

      expect(@users.count).to eq(1)

      @users.remove()
      block_run = false

      fixturize "with enabled = false" do
        block_run = true
        @users.insert(:first_name => "Scott")
      end
      expect(block_run).to eq(true)
      expect(@users.count).to eq(1)
    end
  end

  describe "clearing the cache" do
    it "should drop data from the current version" do
      Fixturize.database_version = 1

      fixturize do
        @users.insert(:first_name => "Scott")
      end

      expect(Fixturize.collection.count).to eq(1)
      Fixturize.clear_cache!
      expect(Fixturize.collection.count).to eq(0)
    end
  end

  describe "dropping old versions" do
    it "should not drop data from the current version" do
      Fixturize.database_version = 1

      fixturize do
        @users.insert(:first_name => "Scott")
      end

      expect(Fixturize.collection.count).to eq(1)
      Fixturize.clear_old_versions!
      expect(Fixturize.collection.count).to eq(1)
    end

    it "should drop data from an old version" do
      Fixturize.database_version = 1

      fixturize do
        @users.insert(:first_name => "Scott")
      end

      expect(Fixturize.collection.count).to eq(1)

      Fixturize.database_version = 2
      Fixturize.clear_old_versions!
      Fixturize.database_version = 1

      expect(Fixturize.collection.count).to eq(0)
    end
  end
end