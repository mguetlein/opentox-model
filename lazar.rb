require "haml" 

helpers do
  def uri_available?(urlStr)
    url = URI.parse(urlStr)
    unless @subjectid
      Net::HTTP.start(url.host, url.port) do |http|
        return http.head(url.request_uri).code == "200"
      end
    else
      Net::HTTP.start(url.host, url.port) do |http|
        return http.post(url.request_uri, "subjectid=#{@subjectid}").code == "202"
      end
    end
  end
end

# Get model representation
# @return [application/rdf+xml,application/x-yaml] Model representation
get '/:id/?' do

	accept = request.env['HTTP_ACCEPT']
	accept = "application/rdf+xml" if accept == '*/*' or accept == '' or accept.nil?
	# workaround for browser links
	case params[:id]
	when /.yaml$/
		params[:id].sub!(/.yaml$/,'')
		accept =  'application/x-yaml'
	when /.rdf$/
		params[:id].sub!(/.rdf$/,'')
		accept =  'application/rdf+xml'
	end
	halt 404, "Model #{params[:id]} not found." unless model = ModelStore.get(params[:id])
  lazar = YAML.load model.yaml
	case accept
	when /application\/rdf\+xml/
    s = OpenTox::Serializer::Owl.new
    s.add_model(url_for('/lazar',:full),lazar.metadata)
    response['Content-Type'] = 'application/rdf+xml'
    s.to_rdfxml
	when /yaml/
		response['Content-Type'] = 'application/x-yaml'
		model.yaml
	else
		halt 400, "Unsupported MIME type '#{accept}'"
	end
end

get '/:id/metadata.?:ext?' do

  metadata = YAML.load(ModelStore.get(params[:id]).yaml).metadata

  accept = request.env['HTTP_ACCEPT']
  accept = "application/rdf+xml" if accept == '*/*' or accept == '' or accept.nil?
  if params[:ext]
    case  params[:ext]
    when "yaml"
      accept = 'application/x-yaml'
    when "rdf", "rdfxml"
      accept = 'application/rdf+xml'
    end
  end
  response['Content-Type'] = accept
  case accept
  when /yaml/
    metadata.to_yaml
  else #when /rdf/ and anything else
    serializer = OpenTox::Serializer::Owl.new
    serializer.add_metadata url_for("/#{params[:id]}",:full), metadata
    serializer.to_rdfxml
  end

end

# Store a lazar model. This method should not be called directly, use OpenTox::Algorithm::Lazr to create a lazar model
# @param [Body] lazar Model representation in YAML format
# @return [String] Model URI
post '/?' do # create model
  halt 400, "MIME type \"#{request.content_type}\" not supported." unless request.content_type.match(/yaml/)
  model = ModelStore.create
  model.subjectid = @subjectid
  model.uri = url_for("/#{model.id}", :full)
  lazar =	YAML.load request.env["rack.input"].read
  lazar.uri = model.uri
  model.yaml = lazar.to_yaml
  model.save
  model.uri
end

# Make a lazar prediction. Predicts either a single compound or all compounds from a dataset 
# @param [optional,String] dataset_uri URI of the dataset to be predicted
# @param [optional,String] compound_uri URI of the compound to be predicted
# @param [optional,Header] Accept Content-type of prediction, can be either `application/rdf+xml or application/x-yaml`
# @return [text/uri-list] URI of prediction task (dataset prediction) or prediction dataset (compound prediction)
post '/:id/?' do

	@lazar = YAML.load ModelStore.get(params[:id]).yaml
  
	halt 404, "Model #{params[:id]} does not exist." unless @lazar
	halt 404, "No compound_uri or dataset_uri parameter." unless compound_uri = params[:compound_uri] or dataset_uri = params[:dataset_uri]

  response['Content-Type'] = 'text/uri-list'

	if compound_uri
    cache = PredictionCache.first(:model_uri => @lazar.uri, :compound_uri => compound_uri)
    return cache.dataset_uri if cache and uri_available?(cache.dataset_uri)
    begin
      prediction_uri = @lazar.predict(compound_uri,true,@subjectid).uri
      PredictionCache.create(:model_uri => @lazar.uri, :compound_uri => compound_uri, :dataset_uri => prediction_uri)
      prediction_uri
    rescue
      LOGGER.error "Lazar prediction failed for #{compound_uri} with #{$!} "
      halt 500, "Prediction of #{compound_uri} with #{@lazar.uri} failed."
    end
	elsif dataset_uri
		task = OpenTox::Task.create("Predict dataset",url_for("/#{@lazar.id}", :full)) do
      @lazar.predict_dataset(dataset_uri, @subjectid).uri
	  end
    halt 503,task.uri+"\n" if task.status == "Cancelled"
    halt 202,task.uri
	end

end
