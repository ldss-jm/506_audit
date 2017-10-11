require 'set'
require_relative 'Collection'


class Record
  attr_accessor :_773, :_506, :_506s_needed, :_506s_deleted, :_506_action,
                :bnum

  def initialize(hsh)
    @hsh = hsh
    @bnum = hsh['bnum']
    @_773 = Set.new(hsh['_773s'].
                    to_s.
                    gsub(/^(\|6880-05)?\|t/, '').
                    gsub(/;;;(\|6880-05)?\|t/, ';;;').
                    split(';;;')).delete(nil)
    @_506 = Set.new(hsh['_506s'].to_s.split(';;;'))
  end

  def _773s()
    return @_773.to_a.join("|")
  end

  def _506s()
    return @_506.to_a.join("|")
  end

  def collections(colls)
    collector = []
    @_773.each do |_773|
      if colls.include?(_773)
        collector << colls[_773]
      else
        # collection not found
        return nil
      end
    end
    return collector
  end

  def error_bib_string()
    return [@bnum, @_506.to_a.join("|"), @_773.to_a.join("|")].join("\t") + "\n"
  end

  def write_error(errorfile, bib_string)
    guarantee_ofile(errorfile) << bib_string
  end

  # removes whitelisted non-confirming 506s from the proper/actual comparison,
  # sets has_whitelisted so that 506s could be added normally but 506s can't be
  # included with normal deletes
  #
  def strip_whitelisted(actual)
  initial_length = actual.length
  whitelisted = [
    '|aAccess limited to UNC Chapel Hill-authenticated users and to content added to the resource through the 2015 calendar year. After 2015, content may be added to which UNC users do not have full text access.|fUnlimited simultaneous users',
    "|aUNC Library's One-Time Purchase of this title in 2013 gave our patrons access to the content that was available at the time of purchase.  It also included all material added or updated during 2013."
  ]
  whitelisted.each do |okay_506|
    actual.delete(okay_506)
  end
  if initial_length > actual.length
    @has_whitelisted_506=true
  end
  return actual
  end

  def check_506s(colls)
    actual = @_506.delete(nil)
    proper = Set.new()
    my_colls = collections(colls)
    if not my_colls
      #collection not found
      @_506_action = 'error'
      write_error('output_ERROR_coll_not_found.txt', error_bib_string)
      return nil
    end
    my_colls.each do |coll|
      coll_proper_506 = coll.gen_proper_506(include_x856=false)
      if coll_proper_506 == 'ERROR. Collection not modifiable'
        write_error('output_WARNING_coll_not_modifiable.txt', error_bib_string)
        return nil
      elsif coll_proper_506.include?('Conc Users')
        write_error('output_WARNING_varies_by_title.txt', error_bib_string)
        return nil
      elsif coll_proper_506.include?('No number word')
        write_error('output_ERROR_concuser_value.txt', error_bib_string)
        return nil
      end
      if coll.bad_506
        #Errors with one of the collections
        @_506_action = 'error'
        write_error('output_ALERT_general_coll_problem.txt', error_bib_string)
        return nil
      end
      proper << coll_proper_506
    end
    # if there are multiple unique 506s, need to get x856s
    if proper.length > 1
      proper = Set.new()
      collections(colls).each do |coll|
        if coll.gen_proper_506(include_x856=true).include? 'No x856'
          #Errors with a needed x856
          @_506_action = 'error'
          write_error('output_ALERT_coll_need_x856.txt', "#{coll._773}\t" + error_bib_string)
          return nil
        end
        proper << coll.gen_proper_506(include_x856=true)
      end
    end
    if proper == strip_whitelisted(actual)
      @_506_action = nil
    elsif proper.superset?(actual)
      @_506_action = "add"
      @_506s_needed = proper.difference(actual)
    else
      @_506_action = "delete"
      @_506s_needed = proper
      @_506s_deleted = actual.difference(@_506s_needed)
      if @has_whitelisted
        @_506_action = 'error'
        write_error('output_ALERT_delete_needed_w_whitelisted_506.txt', error_bib_string)
        return nil
      end
    end
    return @_506_action
  end
end