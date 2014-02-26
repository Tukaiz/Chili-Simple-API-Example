class ChiliPublisherUri
  def self.url_for(options = {})
    URI::HTTP.build host:         'dev1.chili-publish.com',
                    path:         options.fetch(:path,  nil),
                    query:        options.fetch(:query, nil),
                    content_type: options.fetch(:content_type, nil)
  end
end
