
# fixturize

## What problem does it solve?

  Rails tests often create expensive objects in before(:each) / setup
  which gets shared between multiple tests.

  Usually it's not inserting the raw data which takes a majority of the time;
  rather it's the instantiation and callbacks.  So why not perform raw inserts instead?

## Example

    describe User do
      before :each do
        fixturize do
          @user = FactoryGirl.create(:user)
        end
      end

      it "should run this block faster the second time" do
        expect(@user.class).to eq(User)
      end
    end

## Install

Gemfile:

    group :test do
      gem 'fixturize'
    end

spec_helper.rb:

   Fixturize.version = 1 # bump this if you change the source of a block
   Fixturize.database = MongoMapper.database
   Fixturize.enabled = true

   # (only if you wipe your db between test runs):
   RSpec.configure do |config|
     def wipe_db
       MongoMapper.database.collections.each do |c|
         unless (c.name =~ /system/ || Fixturize.collection_name == c.name)
           c.remove()
         end
       end
     end

     config.before(:each) do
       wipe_db
     end
   end

## FAQ

TODO!