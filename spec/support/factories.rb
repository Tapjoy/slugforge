def create_slug(project, name, content = "blag")
  bucket = helpers.s3.directories.new(:key => 'tj-slugforge')
  bucket.files.create :key => "#{project}/#{name}.slug", :body => "blah"
end

def create_tag(project, tag, slug)
  bucket = helpers.s3.directories.new(:key => 'tj-slugforge')
  bucket.files.create :key => "#{project}/tags/#{tag}", :body => slug
end

def build_sts_response
  double('STS Response', :body => {
    'AccessKeyId' => "access-#{rand(1000)}",
    'SecretAccessKey' => "secret-#{rand(1000)}",
    'SessionToken' => "session-#{rand(1000)}"
    })
end
