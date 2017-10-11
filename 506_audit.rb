require 'fileutils'
require 'csv'
require_relative 'Collection'
require_relative 'Record'


def guarantee_ofile(filename)
  $ofiles[filename] = File.open(filename, 'w') unless $ofiles.include?(filename)
  return $ofiles[filename]
end

def write_add(record, stem='')
  record._506s_needed.to_a.each do |_506|
    if _506.match(/Unlimited simultaneous/)
      if _506 == '|fUnlimited simultaneous users'
        filename = 'output_CHANGES_' + stem + 'add_OA_unlimited.txt'
      else
        filename = 'output_CHANGES_' + stem + 'add_unlimited.txt'
      end
    else
      conc_users = _506.match(/\(([0-9]*)\) concu/)[1]
      filename = 'output_CHANGES_' + stem + "add_#{conc_users}.txt"
    end
    filename = 'output_CHANGES_' + stem + 'add_x856.txt' if _506.include?("|3")
    guarantee_ofile(filename) << [record.bnum, _506, record._773s].join("\t") + "\n"
    guarantee_ofile('output_DETAILS_all_adds.txt') << [record.bnum, _506, record._773s].join("\t") + "\n"
  end
end

def write_delete(record)
  guarantee_ofile('output_DETAILS_506_deletions.txt') << [record.bnum, record._506s_deleted.to_a.join("|"), record._773s].join("\t") + "\n"
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

$ofiles = {
  'output_DETAILS_all_adds.txt' => File.open('output_DETAILS_all_adds.txt', 'w'),
  'output_DETAILS_506_deletions.txt' => File.open('output_DETAILS_506_deletions.txt', 'w'),
  'output_mult_colls.txt' => File.open('output_mult_colls.txt', 'w')}

# Decide whether or not to run SQL query
#
if File.exist?('output_SQL_results.txt')
  puts "    SQL results already exist. Enter 'run' to run a new query.
    Enter 'skip' to use the old results\n"
  input = gets
  if input.chomp == "run"
    load '506_audit_query.rb'
  else
    puts "using old results"
  end
else
  load '506_audit_query.rb'
end

# Import 773 data to colls
colls={}
collcsv = CSV.read('conc_users_lookup.txt',
             'rb:bom|utf-16:utf-8',
             headers: true,
             header_converters: lambda { |x| x.downcase },
             col_sep: "\t",
             quote_char: "\u0001")
collcsv.each do |entry|
  entry['colltitle7730b'].gsub!('"','')
  colls[entry['colltitle7730b']] = Collection.new(entry)
end

# Process Mil data
puts "processing bibs"
CSV.foreach('output_SQL_results.txt',
             headers: true,
             col_sep: "\t",
             quote_char: "\u0001") do |entry|
  record = Record.new(entry)
  next if record._773s == 'ProQuest U.S. serial set (online collection). 1, 1789-1969. Monographs'
  record.check_506s(colls)
  write_add(record) if record._506_action == 'add'
  write_delete(record) if record._506_action == 'delete'
  if record._773.length > 1
    guarantee_ofile('output_mult_colls.txt') << [record.bnum, record._773.to_a.join("|")].join("\t") + "\n"
  end
end
$ofiles.values.each { |x| x.close }

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
blah = []
all_adds.split("\n").each do |line|
  line_array = line.split("\t")
  any_colls = line_array[0].split('|')
  any_colls.each do |coll|
    blah << line
    all_adds_supplemented << ([coll, colls[coll].marcsource, colls[coll].acctunit] +
                                  line_array.drop(1)
                             ).join("\t") + "\n"
  end
end
File.write('output_SUMMARY_modifiable.txt', all_adds_supplemented)

# Generate a mrk file suitable for Load Profile D
# for records needing a |3
if File.exists?('output_CHANGES_delete_add_x856.txt')
  recs = {}
  File.foreach('output_CHANGES_delete_add_x856.txt') do |line|
    bnum, _506, _773 = line.split("\t")
    if recs.include?(bnum)
      recs[bnum] << _506
    else
      recs[bnum] = [_506]
    end
  end

  fake_ldr = '=LDR  01143cam a22002893u 4500'
  x856_ofile = File.open('del_add_x856.mrk', 'w') do |ofile|
    recs.each do |bnum, _506s|
      _506s.map! { |x| x.tr('|', '$') }
      _506s.map! { |x| x[0..1] == '$f' ? '=506  0\\' + x : '=506  1\\' + x }
      ofile << fake_ldr + "\n"
      ofile << _506s.join("\n") + "\n"
      ofile << '=907  \\\\$a.' + bnum + "\n"
      ofile << "\n"
    end
  end
end
