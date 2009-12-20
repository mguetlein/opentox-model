get '/?' do # get index of models
	Dir["models/*"].collect{|model|  url_for("/", :full) + File.basename(model,".yaml")}.sort.join("\n")
end

get '/:id/?' do

	path = File.join("models",params[:id] + ".yaml")
	halt 404, "Model #{params[:id]} does not exist." unless File.exists? path
	uri = url_for("/lazar/#{params[:id]}", :full)

	accept = request.env['HTTP_ACCEPT']
	accept = "application/rdf+xml" if accept == '*/*' or accept == '' or accept.nil?
	case accept
	when "application/rdf+xml"
		lazar = OpenTox::Model::Lazar.new(path)
		lazar.rdf
	when /yaml/
		send_file path
	else
		status 400
		"Unsupported MIME type '#{request.content_type}'"
	end
end

delete '/:id/?' do
	path = File.join("models",params[:id] + ".yaml")
	if File.exists? path
		File.delete path
		"Model #{params[:id]} deleted."
	else
		halt 404, "Model #{params[:id]} does not exist."
	end
end

post '/?' do # create model

	case request.content_type
	when /yaml/
		input =	request.env["rack.input"].read
		id = Dir["models/*"].collect{|model|  File.basename(model,".yaml").to_i}.sort.last
		if id.nil?
			id = 1
		else
			id += 1
		end
		File.open(File.join("models",id.to_s + ".yaml"),"w+") { |f| f.write input }
		url_for("/#{id}", :full)
	else
		halt 400, "MIME type \"#{request.content_type}\" not supported."
	end

	url_for("/#{id}", :full)

end

# PREDICTIONS
# TODO predict dataset, correct owl format
post '/:id/?' do # create prediction

	path = File.join("models",params[:id] + ".yaml")
	halt 404, "Model #{params[:id]} does not exist." unless File.exists? path
	halt 404, "No compound_uri or dataset_uri parameter." unless compound_uri = params[:compound_uri] or dataset_uri = params[:dataset_uri]
	lazar = OpenTox::Model::Lazar.new(path)

	if compound_uri
		lazar.classify(compound_uri) unless lazar.database_activity?(compound_uri)
	elsif dataset_uri
		input_dataset = OpenTox::Dataset.find(dataset_uri)
		input_dataset.compounds.each do |compound_uri|
			lazar.classify(compound_uri) unless lazar.database_activity?(compound_uri)
		end
	end

	case request.env['HTTP_ACCEPT']
	when /yaml/ 
		lazar.predictions.to_yaml
	else
		if params[:compound_uri]
			lazar.dataset.rdf
		elsif params[:dataset_uri]
			lazar.dataset.save
		end
	end

end

