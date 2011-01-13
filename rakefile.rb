require 'net/http'
require 'xmlsimple'
require 'sanitize'
require 'json'
require 'find'
require 'csv'
require 'prettyprint'
require 'yaml'

require 'open-uri'
require 'uri'

require 'lib/specialities'

@mappings
@specialism_mapping
@intended_audience = /Intended\saudience:<\/strong>\s*(.*?)<\/p>/
@mapping_data_folder = "mapping_data"

task :find_ontology_ids do

  @known_paths = Hash.new
  @new_mappings = []
  
  Find.find(@mapping_data_folder) do |path|
 
    if !FileTest.directory?(path)
      
      CSV.foreach(path) do |row|
        
        # is not the head row and is not exluded from processing
        if row[0] != "TOPIC" and row[3] != "1"
      
          term = row[1]
          
          if @known_paths[term].nil?
            url = "http://ses-test-r4.evidence.nhs.uk/ses?TBDB=disp_taxonomy&TEMPLATE=service.xml&SERVICE=term&TERM=#{URI.escape(term)}"
            puts "retrieving #{url} ..."
                        
            # data = XmlSimple.xml_in open(url) 
            
            data = XmlSimple.xml_in ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n<SEMAPHORE>\r\n\t<PARAMETERS>\r\n\t\t<PARAMETER NAME='TBDB'>disp_taxonomy</PARAMETER>\r\n\t\t<PARAMETER NAME='SERVICE'>term</PARAMETER>\r\n\t\t<PARAMETER NAME='TEMPLATE'>service.xml</PARAMETER>\r\n\t\t<PARAMETER NAME='TERM'>Women&apos;s Health</PARAMETER>\r\n\t</PARAMETERS>\r\n\t<TERMS>\r\n\t\t<TERM SRC='1' INDEX='disp_taxonomy' RANK='0' PERCENTAGE='86' WEIGHT='16.6908'>\r\n\t\t\t<NAME>Women&apos;s Health</NAME>\r\n\t\t\t<ID>253550</ID>\r\n\t\t\t<DISPLAY_NAME>Women&apos;s Health</DISPLAY_NAME>\r\n\t\t\t<FREQUENCY>0</FREQUENCY>\r\n\t\t\t<PATH TYPE='Narrower Term' ABBR='NT'>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='565220' NAME='term'>NHS Evidence</FIELD>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='276199' NAME='term'>MeSH (purged)</FIELD>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='219952' NAME='term'>Health Care</FIELD>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='219055' NAME='term'>Population Characteristics</FIELD>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='220290' NAME='term'>Health</FIELD>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='253550' NAME='term'>Women&apos;s Health</FIELD>\r\n\t\t\t</PATH>\r\n\t\t\t<HIERARCHY TYPE='Broader Term' ABBR='BT'>\r\n\t\t\t\t<FIELD FACET0='NHS Evidence' FACET_ID0='565220' FREQ='0' ID='220290' NAME='term'>Health</FIELD>\r\n\t\t\t</HIERARCHY>\r\n\t\t\t<FACETS>\r\n\t\t\t\t<FACET NAME='NHS Evidence' ID='565220' />\r\n\t\t\t</FACETS>\r\n\t\t\t<ATTRIBUTE>\r\n\t\t\t\t<FIELD NAME='A-Z Entry'>1</FIELD>\r\n\t\t\t\t<FIELD NAME='Use for classifying content'>1</FIELD>\r\n\t\t\t\t<FIELD NAME='Significant Term'>0</FIELD>\r\n\t\t\t\t<FIELD NAME='Do not use for concept mapping'>0</FIELD>\r\n\t\t\t\t<FIELD NAME='TopicArea'>0</FIELD>\r\n\t\t\t\t<FIELD NAME='Topic'>0</FIELD>\r\n\t\t\t</ATTRIBUTE>\r\n\t\t\t<METADATA>\r\n\t\t\t\t<FIELD NAME='MeSH ID'>D016387</FIELD>\r\n\t\t\t\t<FIELD NAME='Tree Number'>N01.400.900</FIELD>\r\n\t\t\t</METADATA>\r\n\t\t\t<SYNONYMS TYPE='Use' ABBR='USE'>\r\n\t\t\t\t<SYNONYM ID='155088'>Health, Woman&apos;s</SYNONYM>\r\n\t\t\t\t<SYNONYM ID='155084'>Health, Women&apos;s</SYNONYM>\r\n\t\t\t\t<SYNONYM ID='155087'>Woman&apos;s Health</SYNONYM>\r\n\t\t\t\t<SYNONYM ID='155085'>Women Health</SYNONYM>\r\n\t\t\t\t<SYNONYM ID='155086'>Womens Health</SYNONYM>\r\n\t\t\t</SYNONYMS>\r\n\t\t</TERM>\r\n\t</TERMS>\r\n</SEMAPHORE>\r\n", {"ForceArray" => false})
            
            raise "More than one term returned for #{term}, there should only be one" if data["TERMS"].count > 1

            data["TERMS"].each{|term|
              
              term.each{|t|
                p t["RANK"]
                p t["METADATA"]["FIELD"][0]
                p t["HIERARCHY"]
              }
              
            }
          end
          
          term_info = @known_paths[term]
          
          @new_mappings << {
            "SC_TERM" => row[0],
            "MESH_TERM" => row[1],
            "MESH_ID" => row[2],
            "IGNORE" => 0#, # excluding ignored rows already
            #{}"PATH" => term_info.path,
            #{}"ONTOLOGY_ID" => term_info.ontology_id
          }
          
        end
        
      end
      
      # write out new_mappings to CSV...

    end
   end
end

task :generate_mappings do
  
  puts "generating mappings..."
  
  @mappings = Specialities.new

  
  
  Find.find(@mapping_data_folder) do |path|
        
    if !FileTest.directory?(path)
      
      specialism_name = path.split("/")[1].gsub(".csv","")
      
      specialism = @mappings.add(specialism_name)
      
      CSV.foreach(path) do |row|
        
        # is not the head row and is not exluded from processing
        if row[0] != "TOPIC" and row[3] != "1"
          specialism.add(row[0], row[1], row[2])
        end
        
      end
      
      puts "processed #{specialism_name}, #{specialism.length} mapped topics"
      
    end
    
  end
   
  File.open("mappings.yaml", "w") { |file| YAML.dump(@mappings, file) }
  puts "processed mappings written to mappings.yaml"
  
end

# need to call service



task :default => [:generate_mappings] do
  
  Find.find(ENV["folder"]) do |path|
    
      if !FileTest.directory?(path) && path.include?("ok_httpUrl")
        file = path.slice(0,path.index('_')).gsub(ENV["folder"] + '/', '').downcase
        output_folder = File.join('processed', file)
        
        p @mappings
        
        @specialism_mapping = @mappings[file]

        raise "No mappings found for #{file}, please create a CSV file with SC_TERM,MESH_TERM,MESH_ID,IGNORE columns" if @specialism_mapping.nil?
        
        FileUtils.rm_rf output_folder if File.exists? output_folder
                
        puts "Processing #{output_folder}"
        puts "#{@specialism_mapping.count} mappings found"
        
        
        FileUtils.mkdir_p output_folder
        
        data = XmlSimple.xml_in(path)
     
        puts data['document'].count
     
        documents = Array.new
        data['document'].each{ |doc| 
          documents << create_document(doc, file)
        }
        File.open(File.join(output_folder, "all.json"), 'w') { |f|
          f.write(JSON.pretty_generate(documents))
        }
      
      end
   end

end

def create_document (doc, area_of_interest)
    document = Hash.new

    keywords = Sanitize.clean(doc['topics'].to_s.strip_cdata, Sanitize::Config::RELAXED)

    # legacy RMS fields
    document['RMSId'] = doc['id'].to_s
    document['RMSName'] = doc['name'].to_s.strip_cdata.strip
    document['RMSRootDirectory'] = doc['rootDirectory'].to_s.strip_cdata
    document['RMSLastReviewDate'] = doc['lastReviewDate'].to_s.to_date
    document['RMSKeywords'] = keywords

    document['RelatedUrls'] = [] # seek origin
    document['TargetCountry'] = ""
    document['Creator'] = "RMS Import"
    document['ResourceType'] = doc['resourceType'].to_s
    document['Title'] = doc['title'].to_s
    document['TitleForSorting'] = document['Title'].to_sort
    document['Description'] = Sanitize.clean(doc['body'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    document['Url'] = doc['url'].to_s.strip_cdata
    document['Attachment'] = ""
    document['PublicationType'] = doc['publicationType'].to_s.capitalize_each
    
    audience = document['Description'].scan(@intended_audience)[0]
    document['Audience'] = audience[0].to_audiences rescue []
    
    document['PublicationDate'] = doc['publicationDate'].to_s.to_date
    document['ReviewDate']  # seek origin
    document['Source']  = area_of_interest
    document['Publisher'] = doc['publisher'].to_s
    document['Contributor'] = "RMS Import"
    document['ExpiryDate'] = doc['expiryDate'].to_s.to_date
    
    document['Tags'] = map_keywords(keywords.split(","))
    document['AreaOfInterest'] = area_of_interest
    document['CreatedDate'] = Time.now.to_s
    
    # dates = /Date([number])/ - unable to process to this, (to_i) needs (1.9.x)
    # amanda cambell, fran, about about audience and relatedUrls
    # use womenshealth, put through autotagger...
    
    document
end

def map_keywords(keywords)
  tags = []

  keywords.each{|k|
    map = @specialism_mapping[k]
    
    if !map.nil? 
      tags << map.each.collect { |m|
        {
          "Id" => nil,
          "MeshId" => m.mesh_id,
          "Name" => m.term,
          "Path" => nil,
          "Score" => 0.9
        }
      }
    end
  }
  
  tags.flatten!
  # find matching paths, need to add lookup to real terms in ontology (using service)?
end

class String
  def to_audiences
    self.gsub(/\.|\302|\240/, "").split(/,/).collect { |a|  
      a.strip.capitalize_each  }
  end
  
  def to_date
    Date.parse(self) rescue nil
  end
  
  def to_sort
    self.gsub(/[^a-z0-9]+/i, '').downcase
    #self.gsub(/[^\x20-\x7E]/, '').downcase
  end
  def strip_cdata
    self.gsub('<![CDATA[','').gsub(']]>','')
  end
  def capitalize_each
    self.split(" ").each{|word| word.capitalize!}.join(" ")
  end
end