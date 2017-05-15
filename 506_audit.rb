load '../postgres_connect/connect.rb'
require 'fileutils'
require 'set'


class Record
  attr_accessor :_773, :_506, :_506s_needed, :_506s_deleted, :_506_action,
                :bnum

  def initialize(hsh)
    @hsh = hsh
    @bnum = hsh['bnum']
    @_773 = Set.new([hsh['773']]).delete(nil)
    @_506 = Set.new([hsh['506']])
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
    File.open(errorfile, 'a') do |file|
      file << bib_string
    end
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



class Collection
  attr_reader :proper_506, :hsh, :concusers, :acctunit, :marcsource, :_773 , :bad_506

  def initialize(hsh)
    @hsh = hsh
    @_773 = hsh['colltitle7730b']
    @concusers = hsh['concusers']
    @acctunit = hsh['acctunit']
    @marcsource = hsh['uncmarcsrc']
    @x856 = hsh['x856']
    if ['ssna', 'na', '?', '.'].include? @x856 = hsh['x856']
      @x856 = ''
    end
    if @concusers == '999'
      @unlimitedusers = true
    end
    @proper_506 = gen_proper_506
  end

  def gen_proper_506(include_x856=false)
    if not modifiable
      @bad_506 = true
      return "ERROR. Collection not modifiable"
    end
    if @unlimitedusers
      _506 = '|aAccess limited to UNC Chapel Hill-authenticated users.|fUnlimited simultaneous users'
    else
      numeral = @concusers
      number_words = { '1' => 'one', '3' => 'three', '5' => 'five', '6' => 'six', '9' => 'nine', '10' => 'ten', '75' => 'seventy-five'}
      if not number_words.include? numeral
        @bad_506 = true
        if ['vt', 'nav'].include? numeral
          return "ERROR. Conc users varies by title or info not coded for Conc Users value: #{numeral}"
        else
          return "ERROR. No number word matched for: #{numeral}"
        end
      end
      numberword = number_words[numeral]
      _506 = "|aAccess limited to UNC Chapel Hill-authenticated users.|fLimited to #{numberword} (#{numeral}) concurrent users"
      if numeral == '1'
        _506 = _506[0..-2]
      end
    end
    if include_x856 == true
      if @x856.empty?
        return "ERROR. No x856 for collection #{@_773}"
      else
        _506 += "|3#{@x856}"
      end
    end
    if @_773 == 'Getty publications virtual library (online collection)'
      _506 = _506.gsub('Access limited to UNC Chapel Hill-authenticated users',
                      'Freely available resource')
    end
    return _506
  end

  def modifiable()
    @acctunit.include?('UNL') || @marcsource == 'SerialsSolutions'
    # to see only changes to unmodifiable collections, uncomment below
    #!@acctunit.include?('UNL') && @marcsource != 'SerialsSolutions'
  end
end

# Functions begin here
#

#
# Takes a list of each Mil line (lines), and processes lines whose record numeral
# begins with startingnum. colls is the collection info pulled from the collections
# master spreadsheet, and headers are the mil_headers
#
def do_lines(lines, colls, headers, startingnum)
  puts 'reading'
  records = {}
  # Rolls each line into a record (there may be multiple lines per record)
  lines.each do |line|
    if line.match(/^b#{startingnum}/)
      rec = Hash[headers.zip(line.rstrip.split("\t"))]
      rec['773'] = rec['773'].gsub(/^(\|6880-05)?\|t/, '')#.gsub(/^|6880-05/,'')
      bnum = rec['bnum']
      if records.include?(bnum)
        records[bnum]._773 << rec['773']
        records[bnum]._506 << rec['506']
      else
        if rec['773'] != 'ProQuest U.S. serial set (online collection). 1, 1789-1969. Monographs'
          # ignore these for now. presumed pending deletion.
          records[bnum] = Record.new(rec)
        end
      end
    end
  end

  puts 'writing'
  # Checks 506(s) for each record, and writes results
  okay='|aAccess limited to UNC Chapel Hill-authenticated users.|fUnlimited simultaneous users'
  until records.empty? do
    bnum, record = records.shift
    record.check_506s(colls)
    if record._506_action == 'add'
      write_add(record)
    end
    if record._506_action == 'delete'
      write_delete(record)
    end
    if record._773.length > 1
      File.open('output_mult_colls.txt', 'a') do |file|
        file << [record.bnum, record._773.to_a.join("|")].join("\t") + "\n"
      end
    end
  end
end

def write_add(record, stem='')
  record._506s_needed.to_a.each do |_506|
    if _506.match(/Freely available resource/)
      filename = 'output_ALERT_freely_available.txt'
    elsif _506.match(/Unlimited simultaneous/)
      filename = 'output_CHANGES_' + stem + 'add_unlimited.txt'
      if _506.include?("|3")
        filename = 'output_CHANGES_' + stem + 'add_x856.txt'
      end
    else
      conc_users = _506.match(/\(([0-9]*)\) concu/)[1]
      filename = 'output_CHANGES_' + stem + "add_#{conc_users}.txt"
      if _506.include?("|3")
        filename = 'output_CHANGES_' + stem + 'add_x856.txt'
      end
    end
    File.open(filename, 'a') do |file|
      file << [record.bnum, _506, record._773s].join("\t") + "\n"
    end
    File.open('output_DETAILS_all_adds.txt', 'a') do |file|
      file << [record.bnum, _506, record._773s].join("\t") + "\n"
    end
  end
end

def write_delete(record)
  File.open('output_DETAILS_506_deletions.txt', 'a') do |file|
    file << [record.bnum, record._506s_deleted.to_a.join("|"), record._773s].join("\t") + "\n"
  end
  write_add(record, stem='delete_')
end

def summarize(filename, groupby_index)
  if not File.exist?(filename)
    return nil
  end
  summary = ''
  contents  = File.read(filename).split("\n")
  groupings = contents.group_by {|line| line.split("\t")[groupby_index]}
  groupings.each do |k, v|
    example = v.first.split("\t")
    example.delete_at(groupby_index)
    summary << ([k, v.length] + example).join("\t") + "\n"
  end
  sorted = summary.split("\n").sort_by! {|x| x.split("\t")[1].to_i}.reverse
  return sorted.join("\n")
end

def write_summary(filename, groupby_index, ofilename=nil)
  if not File.exist?(filename)
    return nil
  end
  if !ofilename
    ofilename = 'output_SUMMARY_' + filename.downcase
  end
  File.write(ofilename, summarize(filename, groupby_index))
end

#
# Script begins here:
#


write_results('output_SQL_results.txt',
              make_query('all.colls.sql'),
              headers='',
              format='tsv'
)

# import 773 data to colls
lines = []
File.open('conc_users_export.txt', 'rb:bom|utf-16:utf-8') do |f|
  lines = f.read.split("\n")
end
headers = lines.delete_at(0).rstrip.downcase.split("\t")
colls = {}
lines.each do |line|
  coll = Hash[headers.zip(line.rstrip.split("\t"))]
  coll['colltitle7730b'] = coll['colltitle7730b'].gsub('"','')
  colls[coll['colltitle7730b']] = Collection.new(coll)
end

# import Mil data
mil_lines = []
File.open('output_SQL_results.txt', 'rb:bom|utf-16:utf-8') do |f|
  mil_lines = f.read.split("\n")
end
mil_headers = ['bnum', '773', '506']
# loop through the Mil data pulling out record nums beginning with each num
# and processing them.
# It was too much loading all records at once. Each bib record may have multiple
# entries, so can't partition the importing at totally arbitrary places
(0..9).each do |num|
  puts "processing bibs beginning .b#{num}"
  do_lines(mil_lines, colls, mil_headers, num)
end



# Create summary files
#
write_summary('output_ERROR_coll_not_found.txt', 2, 'output_SUMMARY_!error_coll_not_found.txt')
write_summary('output_WARNING_varies_by_title.txt', 2, 'output_SUMMARY_!warning_varies_by_title.txt')
write_summary('output_ERROR_concuser_value.txt', 2, 'output_SUMMARY_!error_concuser_value.txt')
write_summary('output_WARNING_coll_not_modifiable.txt', 2, 'output_SUMMARY_NOT_modifiable.txt')
write_summary('output_DETAILS_506_deletions.txt', 1, ofilename='output_SUMMARY_506s_deleted.txt')
# This is for 506s:
write_summary('output_DETAILS_all_adds.txt', 1, ofilename='output_SUMMARY_506s_added.txt')
# This is for 773s:
#   adds marcsource and acctunit to the summary
all_adds = summarize('output_DETAILS_all_adds.txt', 2)
all_adds_supplemented = ''
all_adds.split("\n").each do |line|
  line_array = line.split("\t")
  any_colls = line_array[0].split('|')
  any_colls.each do |coll|
    all_adds_supplemented << ([coll, colls[coll].marcsource, colls[coll].acctunit] +
                                  line_array.drop(1)
                             ).join("\t") + "\n"
  end
end
File.write('output_SUMMARY_modifiable.txt', all_adds_supplemented)
