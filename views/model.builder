xml.instruct!
xml.model do
	xml.uri url_for("/", :full) + @model.id.to_s
	xml.name @model.name
	xml.training_dataset_uri @model.training_dataset_uri
	xml.feature_dataset_uri @model.feature_dataset_uri
end
