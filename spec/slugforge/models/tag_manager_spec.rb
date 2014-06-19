require 'spec_helper'
require 'slugforge/models/tag_manager'

describe Slugforge::TagManager do

  let(:s3)      { ::Fog::Storage.new(
                  :aws_access_key_id     => 'aws_access_key_id',
                  :aws_secret_access_key => 'aws_secret_access_key',
                  :provider              => 'AWS',
                  :region                => 'us-east-1')
                }
  let(:tm)      { Slugforge::TagManager.new(:s3 => s3, :bucket => 'tj-slugforge') }
  let!(:bucket) { s3.directories.create(:key => 'tj-slugforge') }

  context "projects" do
    it "list of projects should start empty" do
      tm.projects.should be_empty
    end

    context "with a project" do
      before(:each) do
        bucket.files.create(:key => 'project1/test.slug')
        bucket.files.create(:key => 'project2/test.slug')
      end

      it "list of projects should include all projects" do
        tm.projects.should include("project1")
        tm.projects.should include("project2")
      end
    end
  end

  context "tags" do
    before(:each) do
      bucket.files.create(:key  => 'project1/test.slug')
      bucket.files.create(:key  => 'project2/test.slug')
      bucket.files.create(
        :key  => 'project2/tags/prod',
        :body => "test.slug\nold.slug"
      )
    end

    context "invalid project" do
      it "lists no tags" do
        tm.tags('bad_project').should be_empty
      end
    end

    context "with no tags" do
      it "lists no tags" do
        tm.tags('project1').should be_empty
      end
    end

    context "with tags" do
      it "lists the tags" do
        tm.tags('project2').should include('prod')
      end

      it "lists only the current slug for the tag" do
        tm.slug_for_tag('project2', 'prod').should include('test.slug')
        tm.slug_for_tag('project2', 'prod').should_not include('old.slug')
      end

      it "lists the slug history for the tag" do
        tm.slugs_for_tag('project2', 'prod').should include('old.slug')
      end

      it "lists the tags for a slug" do
        tm.tags_for_slug('project2', 'test.slug').should include('prod')
      end
    end
  end

end
