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
		lazar = OpenTox::Model::Lazar.new
		lazar.read_yaml(params[:id],File.read(path))
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
		status 404
		"Model #{params[:id]} does not exist."
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
post '/:id/?' do # create prediction

	path = File.join("models",params[:id] + ".yaml")
	halt 404, "Model #{params[:id]} does not exist." unless File.exists? path
	halt 404, "No compound_uri." unless compound_uri = params[:compound_uri]
	lazar = YAML.load_file path
	dataset = OpenTox::Dataset.new

	# find database activities
	if lazar[:activities][compound_uri]
		c = dataset.find_or_create_compound(compound_uri)
		f = dataset.find_or_create_feature(lazar[:endpoint])
		v = dataset.find_or_create_value lazar[:activities][compound_uri].join(',')
		dataset.add_data_entry c,f,v
	else
		#puts compound_uri
		compound = OpenTox::Compound.new(:uri => compound_uri)
		#puts compound.smiles
		#puts compound.inchi
		compound_matches = compound.match lazar[:features]

		conf = 0.0
		neighbors = []
		classification = nil

		lazar[:fingerprints].each do |uri,matches|

			sim = weighted_tanimoto(compound_matches,matches,lazar[:p_values])
			if sim > 0.3
				neighbors << uri
				lazar[:activities][uri].each do |act|
					case act.to_s
					when 'true'
						conf += OpenTox::Utils.gauss(sim)
					when 'false'
						conf -= OpenTox::Utils.gauss(sim)
					end
				end
			end
		end

		conf = conf/neighbors.size
		if conf > 0.0
			classification = true
		elsif conf < 0.0
			classification = false
		end

		c = dataset.find_or_create_compound(compound_uri)
		f = dataset.find_or_create_feature(lazar[:endpoint] + " lazar prediction")
		v = dataset.find_or_create_value classification
		dataset.add_data_entry c,f,v
	
	end

	if /yaml/ =~ params[:type] 
		{ :classification => classification,
			:confidence => conf,
			:neighbors => neighbors,
			:features => compound_matches
		}.to_yaml
	else
		dataset.rdf
	end

end

def weighted_tanimoto(fp_a,fp_b,p)
	common_features = fp_a & fp_b
	all_features = fp_a + fp_b
	common_p_sum = 0.0
	if common_features.size > 0
		common_features.each{|f| common_p_sum += p[f]}
		all_p_sum = 0.0
		all_features.each{|f| all_p_sum += p[f]}
		common_p_sum/all_p_sum
	else
		0.0
	end
end
