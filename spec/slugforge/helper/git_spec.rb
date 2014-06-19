require 'spec_helper'

describe Slugforge::Helper::Git do
  class DummyClass
    attr_accessor :options
  end

  let(:dummy_class)    { DummyClass.new }
  let(:git_account)    { 'GitAccount' }
  let(:git_repository) { 'repository' }
  let(:git_branch)     { 'master' }
  let(:git_remote)     { 'remote' }
  let(:git_url)        { "git@github.com:#{git_account}/#{git_repository}.git" }
  let(:git_sha)        { '0123456789abcdef0123456789abcdef01234567' }

  before(:each) do
    dummy_class.extend(subject)
    dummy_class.stub(:error_class).and_return(Thor::Error)
  end

  context 'not inside work tree' do
    before(:each) { dummy_class.stub(:git_inside_work_tree?).and_return(false) }

    it '#git_account returns nil' do
      dummy_class.git_account.should be_nil
    end
    it '#git_repository returns nil' do
      dummy_class.git_repository.should be_nil
    end
    it '#git_branch returns nil' do
      dummy_class.git_branch.should be_nil
    end
    it '#git_remote returns nil' do
      dummy_class.git_remote.should be_nil
    end
    it '#git_remote_sha returns nil' do
      dummy_class.git_remote_sha.should be_nil
    end
    it '#git_url returns empty' do
      dummy_class.git_url.should be_empty
    end
    it '#git_sha raises' do
      expect { dummy_class.git_sha }.to raise_error(Thor::Error)
    end
  end

  context 'inside work tree' do
    before(:each) { dummy_class.stub(:git_inside_work_tree?).and_return(true) }
    context 'git_url is empty' do
      before(:each) { dummy_class.stub(:git_url).and_return('') }

      it '#git_account returns nil' do
        dummy_class.git_account.should be_nil
      end
      it '#git_repository returns nil' do
        dummy_class.git_repository.should be_nil
      end
    end

    context 'git_url is valid (SSH)' do
      before(:each) { dummy_class.stub(:git_url).and_return(git_url) }

      it '#git_accout returns account' do
        dummy_class.git_account.should == git_account
      end
      it '#git_repository returns repository' do
        dummy_class.git_repository.should == git_repository
      end
    end

    context 'git_url is valid (HTTPS)' do
      let(:git_url) { "https://github.com/#{git_account}/#{git_repository}" }

      before(:each) { dummy_class.stub(:git_url).and_return(git_url) }

      it '#git_accout returns account' do
        dummy_class.git_account.should == git_account
      end
      it '#git_repository returns repository' do
        dummy_class.git_repository.should == git_repository
      end
    end

    describe '#git_remote_sha' do
      before(:each) do
        dummy_class.stub(:git_command).and_return(git_sha)
        dummy_class.stub(:git_url).and_return(git_url)
        dummy_class.stub(:git_branch).and_return(git_branch)
      end

      context 'no options specified' do
        it 'returns first 10 characters of SHA' do
          dummy_class.git_remote_sha.should == git_sha.slice(0...10)
        end
      end

      context 'sha_length specified' do
        it 'returns first character when sha_length=1' do
          dummy_class.git_remote_sha(:sha_length => 1).should == git_sha.slice(0...1)
        end
        
        it 'returns all characters when sha_length=40' do
          dummy_class.git_remote_sha(:sha_length => 40).should == git_sha.slice(0...40)
        end
        
        it 'returns all characters when sha_length>40' do
          dummy_class.git_remote_sha(:sha_length => 50).should == git_sha.slice(0...40)
        end
      end

      context 'url specified' do
        it 'git_command receives url' do
          test_url = 'test_url'
          dummy_class.git_remote_sha(:url => test_url)
          dummy_class.should have_received(:git_command).with("ls-remote #{test_url} #{git_branch}")
        end
      end

      context 'branch specified' do
        it 'git_command receives branch' do
          test_branch = 'test_branch'
          dummy_class.git_remote_sha(:branch => test_branch)
          dummy_class.should have_received(:git_command).with("ls-remote #{git_url} #{test_branch}")
        end
      end
    end

    describe '#git_sha' do
      before(:each) { dummy_class.stub(:git_command).and_return(git_sha) }

      context 'no options specified' do
        it 'returns first 10 characters of SHA' do
          dummy_class.git_sha.should == git_sha.slice(0...10)
        end
      end

      context 'sha_length specified' do
        it 'returns first character when sha_length=1' do
          dummy_class.git_sha(:sha_length => 1).should == git_sha.slice(0...1)
        end
        
        it 'returns all characters when sha_length=40' do
          dummy_class.git_sha(:sha_length => 40).should == git_sha.slice(0...40)
        end
        
        it 'returns all characters when sha_length>40' do
          dummy_class.git_sha(:sha_length => 50).should == git_sha.slice(0...40)
        end
      end
    end
  end
end
