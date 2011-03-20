require 'net/http'
require 'xmlsimple'
require 'sanitize'
require 'json'
require 'find'
require 'csv'
require 'pp'
require 'yaml'

require 'open-uri'
require 'uri'

require Dir.pwd + '/lib/specialities'
require Dir.pwd + '/lib/classify'
require Dir.pwd + '/lib/subjectareas'
require Dir.pwd + '/lib/workstream'

# require 'curb'  #  https://github.com/taf2/curb.git

## TODO
# need to try catorgorize the urls...
# output will look like:
# article url, mapped terms, autocat terms (relevancy...)

# knowledge management mapping file is junk

@mappings
@csv_paths
@specialism_mapping
@intended_audience = /Intended\saudience:<\/strong>\s*(.*?)<\/p>/
@mapping_data_folder = "mapping_data"
@controlled_fields_folder = "controlled_fields"
@publication_types

 
task :generate_csv_paths do
  
  @csv_paths = []
  
  Find.find(@mapping_data_folder) do |path|
    next if FileTest.directory?(path) or path.eql?("#{@mapping_data_folder}/.DS_Store")
    @csv_paths << path if !path.start_with?(".")
  end
  
  @csv_paths
end

task :find_ontology_ids => [:generate_csv_paths] do

  @known_paths = Hash.new
  
  @csv_paths.each{|path|
    @new_mappings = []
    
    
    CSV.foreach(path) do |row|
      
      # is not the head row and is not excluded from processing
      if row[0] != "SC_TERM" and row[3] != "1"
        
        term = row[1].to_s.strip

        if @known_paths[term].nil?
          url = "http://80.71.2.12/ses?TBDB=disp_taxonomy&TEMPLATE=service.json&SERVICE=term&TERM=#{URI.escape(term)}"
          puts "retrieving #{url} ..."

          begin
            f = open(url)
            raw_json = f.read
            data = JSON.parse(raw_json)
          rescue StandardError => boom
            p boom
            data = nil
          end
          
          if data.nil? or data["terms"].nil?
            @known_paths[term] = {
              :path => [],
              :ontology_id => 0
            }
            
            puts "no term mapping found for #{URI.escape(term)}"
          else
            # changed from raise error (raise with Kenny)
            puts "More than one term returned for #{term}, there should only be one" if data["terms"].count > 1
          
            @known_paths[term] = process_term(data)  
          end
    
          
        end

        term_info = @known_paths[term]

        @new_mappings << {
          "SC_TERM" => row[0],
          "MESH_TERM" => row[1],
          "MESH_ID" => row[2],
          "IGNORE" => 0, # excluding ignored rows already
          "ONTOLOGY_ID" => term_info[:ontology_id],
          "PATH" => term_info[:paths].to_json
        }
        
      end
    end
    
    CSV.open("#{@mapping_data_folder}/#{File.basename(path, ".csv")}_converted.csv", "wb") do |csv|
      @new_mappings.each{|m|
        csv << [m["SC_TERM"], m["MESH_TERM"], m["MESH_ID"], m["IGNORE"], m["ONTOLOGY_ID"], m["PATH"]]
      }
    end
  } 
  
end

task :generate_subject_area_mappings do
  import_subject_area_mapping("gastroliver", "Gastrointestinal disorders")
end

def import_subject_area_mapping(name, default_mapping)

  taxonomy_term = ""
  subject_area = []



  mappings = Hash.new

  mappings["DEFAULT"] = default_mapping

  fld_taxonomy_term = 0
  fld_subject_area_1 = 1
  fld_subject_area_2 = 2
  
  CSV.foreach( Dir.pwd + "/#{@controlled_fields_folder}/subjectarea-#{name}.csv") do |row|
    next if row[0].to_s.eql?("TAXONOMY_TERM")
    next if row[fld_subject_area_1].to_s.empty? and subject_area[0].nil?

    if !row[fld_subject_area_1].to_s.empty?
      subject_area = []
      subject_area[0] = row[fld_subject_area_1].to_s if !row[fld_subject_area_1].to_s.empty?
      subject_area[1] = row[fld_subject_area_2].to_s if !row[fld_subject_area_2].to_s.empty?
    end

    mappings[row[fld_taxonomy_term].to_s] = subject_area

  end
  
  @subject_area_mapping[name] = mappings

end


task :generate_publication_types do
  @publication_types = Hash.new
  
  CSV.foreach("#{@controlled_fields_folder}/publicationtype.csv") do |row|
    @publication_types[row[0].to_s.downcase] = row[1]
    @publication_types[row[0].to_s.downcase] = row[0] if row[1].nil?
  end

end

task :generate_publisher_source do
  # CURRENT_PUBLISHER,PUBLISHER,SOURCE,IGNORE

  puts "generating publisher and source mappings..."

  @publisher = Hash.new
  @source = Hash.new

   CSV.foreach("#{@controlled_fields_folder}/publisherandsource.csv") do |row|
     
    next if row[0].to_s == "CURRENT_PUBLISHER"
    next if row[3].to_s == "1"
    
    key = row[0].to_s.downcase

    if !row[1].nil? # map to new publisher
      @publisher[key] = row[1]
    end

    if !row[2].nil? # map to source
      @source[key] = row[2]
    end
  end
  
  puts "#{@source.count} source mappings found."
  puts "#{@publisher.count} publisher mappings found."
end

task :generate_mappings => [:generate_csv_paths, :generate_publication_types, :generate_publisher_source] do
  
  puts "generating mappings..."
  
  @mappings = Specialities.new

  @csv_paths.each{|path|
              
    specialism_name = path.split("/")[1].gsub(".csv","")
    
    specialism = @mappings.add(specialism_name)
    
    CSV.foreach(path) do |row|
      
      # is not the head row and is not exluded from processing
      if row[0] != "TOPIC" and row[3] != "1"
	    	term_path = JSON.parse(row[5]) if row[5] != "null"
    		specialism.add(row[0], row[1], row[2], row[4], term_path)
      end
	  
    end
    
    puts "processed #{specialism_name}, #{specialism.length} mapped topics"
    
  }
   
  File.open("mappings.yaml", "w") { |file| YAML.dump(@mappings, file) }
  puts "processed mappings written to mappings.yaml"
  
end

task :map_subjects do
  name = ENV["name"]
  keywords = ENV["keywords"]
  map_subject_area(name, keywords)
end

task :default => [:generate_mappings] do  
  Find.find(ENV["folder"]) do |path|
    
      if !FileTest.directory?(path) && path.include?("ok_httpUrl")
        
        file = File.basename(path, ".xml")
        file = file.slice(0,file.index('_')).downcase
        
        output_folder = File.join('processed', file)
        
        @specialism_mapping = @mappings[file]
        
        
        FileUtils.rm_rf output_folder if File.exists? output_folder
                
        puts "Processing #{output_folder}"
        puts "#{@specialism_mapping.count} mappings found" unless @specialism_mapping.nil?
        puts "No mappings found for #{file}, please create a CSV file named #{file}.csv with SC_TERM,MESH_TERM,MESH_ID,IGNORE columns" if @specialism_mapping.nil?
        
        
        FileUtils.mkdir_p output_folder
        
        data = XmlSimple.xml_in(path)
     
        puts data['document'].count
     
        documents = Array.new
        data['document'].each{ |doc| 
          
          document = create_document(doc, file)
          
          documents << document if include?(document)
        }
        File.open(File.join(output_folder, "all.json"), 'w') { |f|
          f.write(JSON.pretty_generate(documents))
        }
      
      end
   end

end

def include?(document)
  publication_type = document["PublicationType"]
  title = document["Title"]
    
  if publication_type.eql?("Evidence updates") or publication_type.eql?("Narrative reviews") or title.downcase.include?(" annual evidence update on ")
    false
  else
    true
  end
end


def create_document (doc, area_of_interest)
    document = Hash.new

    keywords = Sanitize.clean(doc['topics'][0].to_s.strip_cdata.strip, Sanitize::Config::RELAXED)
    # legacy RMS fields
    document['RMSId'] = doc['id'][0].to_s
    document['RMSName'] = doc['name'][0].to_s.strip_cdata.strip
    document['RMSRootDirectory'] = doc['rootDirectory'][0].to_s.strip_cdata
    document['RMSKeywords'] = keywords

    document['RelatedUrls'] = [] # seek origin
    document['TargetCountry'] = []
    
    document['Title'] = doc['title'][0].to_s
    document['Description'] = Sanitize.clean(doc['body'][0].to_s.strip_cdata, Sanitize::Config::RELAXED)
    document['Url'] = doc['url'][0].to_s.strip_cdata
    document['Attachment'] = "" # not doing anything with attached files?
    
    document['PublicationType'] = map_publication_type(doc['publicationType'][0].to_s)
        
    publisher = doc['publisher'][0].to_s.strip
    
    document['Source'] = map_source(publisher, doc['creator'].to_s.split(", "))[0].to_s
    document['Publisher'] = map_publisher(publisher)
    
    audience = document['Description'].scan(@intended_audience)[0]
    document['Audience'] = audience[0].to_audiences rescue []
    
    document['PublicationDate'] = doc['publicationDate'].to_s.to_date
    document['ReviewDate'] = doc['expiryDate'].to_s.to_date
    
    document['ExpiryDate'] = doc['expiryDate'].to_s.to_date
    
    document['Tags'] = map_keywords(keywords.split(",")) unless @specialism_mapping.nil?
    document['AreaOfInterest'] = [area_of_interest]
    document['CreatedDate'] = Time.now.to_s.to_date
    
    document['Contributor'] = doc['creator'].to_s.split(", ")
    
    document['SubjectArea'] = map_subject_area(area_of_interest, keywords)
    
    # these are used primarily in the import process... and yes, the last edited by is the same as the process creator - as advised by Fran W
    document['ImportProcesCreator'] = doc['name'][0].to_s.strip_cdata
    document['ImportLastEditedBy'] = document['ImportProcesCreator']
    
    if area_of_interest.eql?("qipp")
      document["QIPPWorkstreams"] = map_qipp_workstreams(keywords)       
      document["Category"] = map_category(keywords)
    end
    
    document
end

def map_qipp_workstreams(keywords)
  # array based on mappings in @workstream  
  qipp_workstreams = []
  keywords.split(",").each{|k|
    qipp_workstreams << @workstream[k] if !@workstream[k].nil?
  }
  
  qipp_workstreams.uniq
end

def map_category(keywords)
  
  if keywords.split(",").include?("QUALITY AND PRODUCTIVITY COCHRANE TOPICS")
    "Cochrane QIPP"
  else
    "QIPP Case Studies"
  end
  
end

task :test_publisher => [:generate_publisher_source] do
  map_publisher(ENV['publisher'])
end

def map_publisher(publisher)
  
  publisher_key = publisher.downcase  
  if !@publisher[publisher_key].nil?
    [@publisher[publisher_key]]
  else
    [publisher]
  end
end

def map_source(publisher, creator)
  source = ""
  publisher_key = publisher.downcase
  if !@source[publisher_key].nil?
    source = @source[publisher_key]
  elsif !creator.nil?
    source = creator
  end
  source
end

def map_subject_area(name, keywords)
  
  mapping = @subject_area_mapping[name]
  
  if !mapping.nil?

  if mapping.is_a?(Array)
    mapping
  elsif mapping.is_a?(Object)
    
    subject_area = []
    
    keywords.split(",").each{|keyword|
      subject_area << mapping[keyword] if !mapping[keyword].nil?
    }
    
    subject_area << mapping["DEFAULT"] if subject_area.empty?
      
    subject_area.flatten.uniq
  end
  end
end

def map_publication_type(in_type)
  mapped_type = @publication_types[in_type.downcase]
   
  if mapped_type.nil?
    [in_type.capitalize_each]
  else
    [mapped_type]
  end
  
end


def map_keywords(keywords)
  tags = []

  keywords.each{|k|
    map = @specialism_mapping[k]
    
    if !map.nil? 
      tags << map.each.collect { |m|
        {
          "Id" => m.term_id,
          "MeshId" => m.mesh_id,
          "Name" => m.term,
          "Path" => {
              "Values" => m.path
            },
          "Score" => 0.9
        }
      }
    end
  }

  tags.flatten!
end

def process_term(data)
  
  term_data = data["terms"][0]["term"]

  term_paths = term_data["paths"]
  
  mapped_paths = []
  
  term_paths.each{|paths|
    mapped_paths << "|" + paths["path"].collect{|path| path["field"]["name"] }.join('|') + "|"
  }
  
  term_info = {
    :paths => mapped_paths,
    :ontology_id => term_data["id"]
  }
end

class String
  def to_audiences
    self.gsub(/\.|\302|\240/, "").split(/,/).collect { |a|  
      a.strip.capitalize_each  }
  end
  
  def to_date
    Date.parse(self).strftime('%Y-%m-%dT%H:%M:%S%z') rescue nil #"that's a no-no #{self}"
  end
  
  def to_sort
    self.gsub(/[^a-z0-9]+/i, '').downcase
  end
  def strip_cdata
    self.gsub('<![CDATA[','').gsub(']]>','')
  end
  def capitalize_each
    self.split(" ").each{|word| word.capitalize!}.join(" ")
  end
end