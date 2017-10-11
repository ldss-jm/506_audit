class Collection
  attr_reader :proper_506, :hsh, :concusers, :acctunit, :marcsource, :_773 , :bad_506

  def initialize(hsh)
    @hsh = hsh
    @_773 = hsh['colltitle7730b']
    @concusers = hsh['concusers']
    @unlimitedusers = true if @concusers == '999'
    @openaccess = true if hsh['own'] == 'n'
    @acctunit = hsh['acctunit']
    @marcsource = hsh['uncmarcsrc']
    @x856 = hsh['x856']
    @x856 = '' if ['ssna', 'na', '?', '.'].include? @x856
    @modifiable = @acctunit.include?('UNL') || @marcsource == 'SerialsSolutions'
    # to see only changes to unmodifiable collections, uncomment below
    #@modifiable = !@acctunit.include?('UNL') && @marcsource != 'SerialsSolutions'
    @proper_506 = gen_proper_506
  end

  def gen_proper_506(include_x856=false)
    if !@modifiable
      @bad_506 = true
      return "ERROR. Collection not modifiable"
    end
    # set |a, |f
    if @openaccess
      _506 = '|fUnlimited simultaneous users'
    elsif @unlimitedusers
      _506 = '|aAccess limited to UNC Chapel Hill-authenticated users.|fUnlimited simultaneous users'
    else
      numeral = @concusers
      number_words = {
        '1' => 'one', '3' => 'three', '5' => 'five', '6' => 'six',
        '9' => 'nine', '10' => 'ten', '75' => 'seventy-five'
}
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
    # add |3 if needed to differentiate access from different collections
    if include_x856 == true
      if @x856.empty?
        return "ERROR. No x856 for collection #{@_773}"
      else
        _506 += "|3#{@x856}"
      end
    end
    return _506
  end
end