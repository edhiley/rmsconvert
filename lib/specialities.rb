class Specialities < Hash
  def add(name)
    self[name] = Speciality.new
  end
end

class Speciality < Hash

  def add(topic_name, term, mesh_id, term_id, path)
    if self[topic_name].nil?
      self[topic_name] = []
    end
    self[topic_name] << TermMapping.new(term, mesh_id, term_id, path)
  end 
end

class TermMapping
  attr_accessor :term, :mesh_id, :term_id, :path
  
  def initialize(term, mesh_id, term_id, path)
    
    term = term.force_encoding("UTF-8").strip if !term.nil?
    mesh_id = mesh_id.force_encoding("UTF-8").strip if !mesh_id.nil?
    term_id = term_id.force_encoding("UTF-8").strip if !term_id.nil?
    
    @term = term
    @mesh_id = mesh_id
    @path = path
    @term_id = term_id
  end

end